package deskts

import (
	"errors"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"sync"

	"tailscale.com/net/netmon"
)

// 안드로이드는 앱에 netlink 를 막아 Go 의 net.Interfaces 가 실패함(tailscale 이슈 2293) — 공식 앱처럼 자바가 알려 준 목록을 씀.
// 한 줄에 한 인터페이스: "이름 번호 MTU up broadcast loopback p2p multicast 주소/길이 ..."
var (
	ifMu   sync.Mutex
	ifList string
)

// SetInterfaces — 자바(NetworkInterface)가 본 인터페이스 목록. 네트워크가 바뀔 때마다 다시 부름
func SetInterfaces(s string) {
	ifMu.Lock()
	ifList = s
	ifMu.Unlock()
}

func init() {
	netmon.RegisterInterfaceGetter(getInterfaces)
}

func getInterfaces() ([]netmon.Interface, error) {
	ifMu.Lock()
	s := ifList
	ifMu.Unlock()
	if s == "" {
		return nil, errors.New("no interfaces from java yet")
	}
	return parseInterfaces(s), nil
}

func parseInterfaces(s string) []netmon.Interface {
	var out []netmon.Interface
	for _, line := range strings.Split(strings.TrimSpace(s), "\n") {
		f := strings.Fields(line)
		if len(f) < 8 {
			continue
		}
		idx, _ := strconv.Atoi(f[1])
		mtu, _ := strconv.Atoi(f[2])
		var flags net.Flags
		for i, fl := range []net.Flags{net.FlagUp, net.FlagBroadcast, net.FlagLoopback, net.FlagPointToPoint, net.FlagMulticast} {
			if f[3+i] == "1" {
				flags |= fl
			}
		}
		if flags&net.FlagUp != 0 {
			flags |= net.FlagRunning
		}
		addrs := []net.Addr{}
		for _, a := range f[8:] {
			if p, err := netip.ParsePrefix(a); err == nil {
				addrs = append(addrs, &net.IPNet{IP: p.Addr().AsSlice(), Mask: net.CIDRMask(p.Bits(), p.Addr().BitLen())})
			}
		}
		out = append(out, netmon.Interface{Interface: &net.Interface{Index: idx, MTU: mtu, Name: f[0], Flags: flags}, AltAddrs: addrs})
	}
	return out
}
