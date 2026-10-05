package lab.desk.phone;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Bundle;
import android.speech.tts.TextToSpeech;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InterfaceAddress;
import java.net.NetworkInterface;
import java.net.URL;
import java.util.Collections;
import java.util.Locale;

/** 책상 비서 — 앱 안의 Tailscale(deskts, tsnet)로 테일넷에 붙어 맥(deskd 폰 서버)의 화면을 WebView 로 띄우고,
 *  누르고 말하기 녹음 · 답 읽기만 여기서 함. 폰에 Tailscale 앱은 필요 없음 — 처음 한 번 앱 안에서 로그인. */
public class MainActivity extends Activity {
    static final int SR = 16000;
    static final int MAX_BYTES = SR * 2 * 90;               // 90초까지

    WebView web;
    TextToSpeech tts;
    volatile boolean recording;
    ByteArrayOutputStream pcm;
    Thread recThread;

    String base;                                          // http://127.0.0.1:<프록시> — 테일넷으로 맥에 닿음
    final Handler ui = new Handler(Looper.getMainLooper());
    String shownLogin = "";
    boolean loaded;

    String home() { return base + "/?t=" + Secrets.TOKEN; }

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        web.addJavascriptInterface(new Bridge(), "DeskApp");
        web.setWebViewClient(new WebViewClient() {
            @Override public void onReceivedError(WebView v, WebResourceRequest req, WebResourceError err) {
                if (req.isForMainFrame()) offline(String.valueOf(err.getDescription()));
            }
        });
        setContentView(web);
        tts = new TextToSpeech(this, st -> { if (st == TextToSpeech.SUCCESS) tts.setLanguage(Locale.KOREAN); });
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 1);
        deskts.Deskts.setInterfaces(interfaces());
        try {
            ((ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE)).registerDefaultNetworkCallback(
                new ConnectivityManager.NetworkCallback() {
                    @Override public void onAvailable(Network n) { deskts.Deskts.setInterfaces(interfaces()); }
                    @Override public void onLost(Network n) { deskts.Deskts.setInterfaces(interfaces()); }
                });
        } catch (Exception ignored) { }
        try {
            long port = deskts.Deskts.start(getFilesDir() + "/tailscale", "desk-phone", Secrets.TARGET);
            base = "http://127.0.0.1:" + port;
        } catch (Exception e) {
            page("Tailscale 을 시작하지 못했어요", String.valueOf(e.getMessage()), "");
            return;
        }
        page("맥에 연결하는 중…", "", "");
        ui.post(this::watch);
    }

    /** 테일넷 상태를 보고 로그인 화면 · 비서 화면을 고름. 붙은 뒤에도 끊기면(키 만료 등) 다시 로그인 화면 */
    void watch() {
        new Thread(() -> {
            String st = deskts.Deskts.status();
            String url = "NeedsLogin".equals(st) ? deskts.Deskts.authURL() : "";
            ui.post(() -> {
                if ("Running".equals(st)) {
                    if (!loaded) { loaded = true; web.loadUrl(home()); }
                } else if ("NeedsLogin".equals(st) || "NeedsMachineAuth".equals(st)) {
                    loaded = false;
                    if (!url.equals(shownLogin)) {
                        shownLogin = url;
                        if ("NeedsMachineAuth".equals(st))
                            page("관리 화면에서 이 기기를 승인해 주세요", "Tailscale 관리 화면에서 desk-phone 을 승인하면 바로 이어져요.", "");
                        else if (url.isEmpty())
                            page("로그인 준비 중…", "", "");
                        else
                            page("처음 한 번만 로그인", "맥과 같은 Tailscale 계정으로 로그인하면, 그 뒤로는 어디서든 이 앱만 열면 돼요.", url);
                    }
                } else if (st.startsWith("Error")) {
                    page("Tailscale 오류", st, "");
                }
                ui.postDelayed(this::watch, loaded ? 5000 : 1500);
            });
        }).start();
    }

    void page(String title, String text, String loginUrl) {
        String btn = loginUrl.isEmpty() ? "" : "<p><button style='font-size:22px;padding:16px 30px;border-radius:12px;border:0;background:#1f6feb;color:#fff' onclick='DeskApp.login()'>Tailscale 로그인</button></p>";
        String html = "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"
            + "<body style='background:#0d1117;color:#e6edf3;font-family:sans-serif;padding:28px;font-size:18px'>"
            + "<h2>" + esc(title) + "</h2><p>" + esc(text) + "</p>" + btn + "</body></html>";
        web.loadDataWithBaseURL(null, html, "text/html", "utf-8", null);
    }

    /** 안드로이드는 Go 에 netlink 를 막아서 — 자바가 본 인터페이스 목록을 넘김 (deskts/ifaces.go 형식) */
    static String interfaces() {
        StringBuilder b = new StringBuilder();
        try {
            for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                b.append(ni.getName()).append(' ').append(ni.getIndex()).append(' ').append(ni.getMTU())
                 .append(ni.isUp() ? " 1" : " 0").append(" 1").append(ni.isLoopback() ? " 1" : " 0")
                 .append(ni.isPointToPoint() ? " 1" : " 0").append(ni.supportsMulticast() ? " 1" : " 0");
                for (InterfaceAddress a : ni.getInterfaceAddresses()) {
                    String ip = a.getAddress().getHostAddress();
                    int z = ip.indexOf('%');
                    if (z >= 0) ip = ip.substring(0, z);
                    b.append(' ').append(ip).append('/').append(a.getNetworkPrefixLength());
                }
                b.append('\n');
            }
        } catch (Exception ignored) { }
        return b.toString();
    }

    static String esc(String s) { return s.replace("&", "&amp;").replace("<", "&lt;"); }

    void offline(String why) {
        loaded = true;                                     // watch 가 덮어쓰지 않게 — 다시 연결 버튼으로
        String html = "<html><body style='background:#0d1117;color:#e6edf3;font-family:sans-serif;padding:24px;font-size:18px'>"
            + "<h2>맥에 닿지 않아요</h2><p>폰 인터넷이 되는지, 맥(mybody-mac)이 켜져 있는지 봐 주세요.</p>"
            + "<p style='color:#8b949e;font-size:14px'>" + esc(why) + "</p>"
            + "<button style='font-size:20px;padding:14px 28px' onclick='DeskApp.retry()'>다시 연결</button></body></html>";
        web.loadDataWithBaseURL(null, html, "text/html", "utf-8", null);
    }

    @Override public void onBackPressed() {
        if (web.canGoBack()) web.goBack(); else super.onBackPressed();
    }

    @Override protected void onDestroy() {
        recording = false;
        if (tts != null) tts.shutdown();
        super.onDestroy();
    }

    void js(String fn, String arg) {
        runOnUiThread(() -> web.evaluateJavascript(fn + "(" + JSONObject.quote(arg) + ")", null));
    }

    class Bridge {
        @JavascriptInterface public void retry() { runOnUiThread(() -> web.loadUrl(home())); }

        @JavascriptInterface public void login() {
            if (!shownLogin.isEmpty()) startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(shownLogin)));
        }

        @JavascriptInterface public void speak(String text) {
            if (tts != null) tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "desk");
        }

        @JavascriptInterface public void stopSpeak() { if (tts != null) tts.stop(); }

        @JavascriptInterface public void startTalk() {
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                runOnUiThread(() -> requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 1));
                js("deskReply", "{\"reply\":\"마이크 권한을 허용해 주세요.\"}");
                return;
            }
            if (recording) return;
            int min = AudioRecord.getMinBufferSize(SR, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
            final AudioRecord rec;
            try {
                rec = new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, SR, AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT, Math.max(min, SR));
                rec.startRecording();
            } catch (Exception e) {
                js("deskReply", "{\"reply\":\"마이크를 열지 못했어요.\"}");
                return;
            }
            pcm = new ByteArrayOutputStream();
            recording = true;
            recThread = new Thread(() -> {
                byte[] buf = new byte[3200];
                while (recording && pcm.size() < MAX_BYTES) {
                    int n = rec.read(buf, 0, buf.length);
                    if (n > 0) pcm.write(buf, 0, n);
                }
                rec.stop();
                rec.release();
            });
            recThread.start();
        }

        @JavascriptInterface public void stopTalk() {
            if (!recording && recThread == null) return;
            recording = false;
            final Thread t = recThread;
            recThread = null;
            new Thread(() -> {
                try { if (t != null) t.join(2000); } catch (InterruptedException ignored) { }
                byte[] body = pcm == null ? new byte[0] : pcm.toByteArray();
                if (body.length < SR / 2) {                       // 0.25초보다 짧음 — 잠깐 누른 것
                    js("deskReply", "{\"reply\":\"\",\"kind\":\"local-silent\"}");
                    return;
                }
                js("deskStatus", "받아쓰고 생각 중…");
                js("deskReply", post("/talk", body));
            }).start();
        }
    }

    String post(String path, byte[] body) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(base + path).openConnection();
            c.setConnectTimeout(8000);
            c.setReadTimeout(240000);
            c.setDoOutput(true);
            c.setRequestMethod("POST");
            c.setRequestProperty("X-Desk-Token", Secrets.TOKEN);
            c.setRequestProperty("Content-Type", "audio/L16; rate=16000; channels=1");
            c.setFixedLengthStreamingMode(body.length);
            try (OutputStream o = c.getOutputStream()) { o.write(body); }
            InputStream in = c.getResponseCode() < 400 ? c.getInputStream() : c.getErrorStream();
            ByteArrayOutputStream r = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) r.write(buf, 0, n);
            String s = r.toString("UTF-8");
            if (c.getResponseCode() >= 400) return new JSONObject().put("reply", "맥이 거절했어요 (" + c.getResponseCode() + ").").toString();
            return s;
        } catch (Exception e) {
            try {
                return new JSONObject().put("reply", "맥에 닿지 않아요. 인터넷 연결을 봐 주세요.").toString();
            } catch (Exception ignored) { return "{}"; }
        } finally {
            if (c != null) c.disconnect();
        }
    }
}
