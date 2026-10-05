// Package deskts — 비서 앱 안의 Tailscale(tsnet). 폰에 Tailscale 앱을 따로 깔지 않고, 앱이 테일넷의 한 기기로 붙어
// 127.0.0.1:<port> 로 받은 요청을 맥(deskd 폰 서버)으로 넘김. 공개 인터넷에는 아무것도 열지 않음.
package deskts

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"tailscale.com/client/local"
	"tailscale.com/tsnet"
)

var (
	mu   sync.Mutex
	srv  *tsnet.Server
	port int
	ferr string
)

// Start — dir: 앱 전용 폴더(로그인 키 저장), target: "100.83.32.36:7071". 로컬 프록시 포트를 돌려줌(로그인 전에도 바로)
func Start(dir, hostname, target string) (int, error) {
	mu.Lock()
	defer mu.Unlock()
	if srv != nil {
		return port, nil
	}
	os.Setenv("TS_NO_LOGS_NO_SUPPORT", "true")
	// 안드로이드 앱엔 HOME · 캐시 · 임시 폴더가 없어 logpolicy 가 "no safe place found to store log state" 로 죽음 — 앱 폴더로
	for k, sub := range map[string]string{"HOME": "home", "XDG_CACHE_HOME": "cache", "TMPDIR": "tmp"} {
		d := filepath.Join(dir, sub)
		os.MkdirAll(d, 0o700)
		os.Setenv(k, d)
	}
	s := &tsnet.Server{Dir: dir, Hostname: hostname, Logf: keep, UserLogf: keep}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	u, _ := url.Parse("http://" + target)
	rp := httputil.NewSingleHostReverseProxy(u)
	rp.FlushInterval = -1
	rp.Transport = &http.Transport{DialContext: s.Dial, ResponseHeaderTimeout: 300 * time.Second, IdleConnTimeout: 60 * time.Second}
	rp.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		http.Error(w, "tailnet: "+err.Error(), http.StatusBadGateway)
	}
	go http.Serve(ln, rp)
	srv, port = s, ln.Addr().(*net.TCPAddr).Port
	go func() {
		if err := s.Start(); err != nil {
			mu.Lock()
			ferr = err.Error()
			mu.Unlock()
		}
	}()
	return port, nil
}

var (
	logMu sync.Mutex
	logs  []string
)

func keep(format string, a ...any) {
	line := fmt.Sprintf(format, a...)
	log.Print(line)
	logMu.Lock()
	logs = append(logs, line)
	if len(logs) > 40 {
		logs = logs[len(logs)-40:]
	}
	logMu.Unlock()
}

// Logs — 최근 tsnet 기록(연결 화면에 작게)
func Logs() string {
	logMu.Lock()
	defer logMu.Unlock()
	return strings.Join(logs, "\n")
}

// Status — "Running" 이면 쓸 수 있음. "NeedsLogin" 이면 AuthURL 로 로그인
func Status() string {
	lc := lclient()
	if lc == nil {
		mu.Lock()
		defer mu.Unlock()
		if ferr != "" {
			return "Error: " + ferr
		}
		return "Starting"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	st, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		return "Starting"
	}
	return st.BackendState
}

// AuthURL — 로그인할 주소(없으면 "")
func AuthURL() string {
	lc := lclient()
	if lc == nil {
		return ""
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	st, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		return ""
	}
	if st.AuthURL == "" && st.BackendState == "NeedsLogin" {
		lc.StartLoginInteractive(ctx)
	}
	return st.AuthURL
}

func lclient() *local.Client {
	mu.Lock()
	s := srv
	mu.Unlock()
	if s == nil {
		return nil
	}
	lc, err := s.LocalClient()
	if err != nil {
		return nil
	}
	return lc
}
