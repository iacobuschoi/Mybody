package lab.desk.phone;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
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
import java.net.URL;
import java.util.Locale;

/** 책상 비서 — 맥(deskd 폰 서버)의 화면을 WebView 로 띄우고, 누르고 말하기 녹음 · 답 읽기만 여기서 함. */
public class MainActivity extends Activity {
    static final int SR = 16000;
    static final int MAX_BYTES = SR * 2 * 90;               // 90초까지

    WebView web;
    TextToSpeech tts;
    volatile boolean recording;
    ByteArrayOutputStream pcm;
    Thread recThread;

    String home() { return Secrets.BASE + "/?t=" + Secrets.TOKEN; }

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
        web.loadUrl(home());
    }

    void offline(String why) {
        String html = "<html><body style='background:#0d1117;color:#e6edf3;font-family:sans-serif;padding:24px;font-size:18px'>"
            + "<h2>맥에 닿지 않아요</h2><p>폰의 <b>Tailscale 앱</b>이 켜져 있고 로그인돼 있는지 봐 주세요."
            + " 맥(mybody-mac)이 켜져 있어야 해요.</p><p style='color:#8b949e;font-size:14px'>" + why.replace("<", "&lt;") + "</p>"
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
            c = (HttpURLConnection) new URL(Secrets.BASE + path).openConnection();
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
                return new JSONObject().put("reply", "맥에 닿지 않아요. Tailscale 이 켜져 있는지 봐 주세요.").toString();
            } catch (Exception ignored) { return "{}"; }
        } finally {
            if (c != null) c.disconnect();
        }
    }
}
