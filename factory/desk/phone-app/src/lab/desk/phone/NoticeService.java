package lab.desk.phone;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/** 앱이 꺼져 있어도 맥(deskd /notices)에 붙어 있다가, 주인 확인이 필요한 일이 생기면 안드로이드 알림으로 띄움.
 *  FCM 없이 테일넷 롱폴 — 같은 알림(id)은 한 번만. */
public class NoticeService extends Service {
    static final String KEEP = "keep", NEED = "need";
    static final long SEEN_MS = 24L * 3600 * 1000;
    volatile boolean run = true;
    Thread loop;

    static void start(Context c) {
        Intent i = new Intent(c, NoticeService.class);
        if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i); else c.startService(i);
    }

    @Override public void onCreate() {
        super.onCreate();
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(KEEP, "연결 유지", NotificationManager.IMPORTANCE_MIN));
        NotificationChannel need = new NotificationChannel(NEED, "주인 확인 필요", NotificationManager.IMPORTANCE_HIGH);
        need.enableVibration(true);
        nm.createNotificationChannel(need);
        Notification keep = new Notification.Builder(this, KEEP)
            .setSmallIcon(R.drawable.ic_stat).setContentTitle("비서 연결 유지 중")
            .setContentText("주인 확인이 필요한 일이 생기면 알려 드려요").setOngoing(true)
            .setContentIntent(open(null, 0)).build();
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, keep, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        else startForeground(1, keep);
        loop = new Thread(this::poll, "notices");
        loop.start();
    }

    @Override public int onStartCommand(Intent i, int flags, int id) { return START_STICKY; }

    @Override public void onDestroy() { run = false; super.onDestroy(); }

    @Override public IBinder onBind(Intent i) { return null; }

    PendingIntent open(String notice, int code) {
        Intent i = new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        if (notice != null) i.putExtra("notice", notice);
        return PendingIntent.getActivity(this, code, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    void poll() {
        SharedPreferences p = getSharedPreferences("notices", MODE_PRIVATE);
        while (run) {
            try {
                String base = Net.base(this);
                if (!"Running".equals(deskts.Deskts.status())) { Thread.sleep(5000); continue; }
                String boot = p.getString("boot", "");
                long since = p.getLong("since", 0);
                JSONObject r = new JSONObject(get(base + "/notices?since=" + since + "&wait=50"));
                if (!r.getString("boot").equals(boot)) {        // deskd 가 다시 떴음 — 처음부터(본 것은 id 로 거름)
                    boot = r.getString("boot");
                    if (since > 0) { p.edit().putString("boot", boot).putLong("since", 0).apply(); continue; }
                }
                JSONObject seen = new JSONObject(p.getString("seen", "{}"));
                long now = System.currentTimeMillis();
                JSONArray items = r.getJSONArray("items");
                for (int k = 0; k < items.length(); k++) {
                    JSONObject it = items.getJSONObject(k);
                    since = Math.max(since, it.getLong("seq"));
                    String key = it.getString("id");
                    boolean fresh = !seen.has(key) || now - seen.getLong(key) > SEEN_MS
                        || it.getLong("at") * 1000 > seen.getLong(key);       // 풀렸다가 다시 막힘
                    if (fresh) notify(it);
                    seen.put(key, now);
                }
                JSONArray names = seen.names();
                for (int k = 0; names != null && k < names.length(); k++)
                    if (now - seen.getLong(names.getString(k)) > 2 * SEEN_MS) seen.remove(names.getString(k));
                p.edit().putString("boot", boot).putLong("since", since).putString("seen", seen.toString()).apply();
            } catch (Exception e) {
                try { Thread.sleep(5000); } catch (InterruptedException ignored) { return; }
            }
        }
    }

    void notify(JSONObject it) throws Exception {
        String id = it.getString("id");
        Notification n = new Notification.Builder(this, NEED)
            .setSmallIcon(R.drawable.ic_stat).setContentTitle(it.optString("title", "주인 확인 필요"))
            .setContentText(it.optString("body")).setStyle(new Notification.BigTextStyle().bigText(it.optString("body")))
            .setAutoCancel(true).setCategory(Notification.CATEGORY_MESSAGE)
            .setContentIntent(open(it.toString(), id.hashCode())).build();
        getSystemService(NotificationManager.class).notify(id.hashCode(), n);
    }

    static String get(String url) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        try {
            c.setConnectTimeout(10000);
            c.setReadTimeout(75000);
            c.setRequestProperty("X-Desk-Token", Secrets.TOKEN);
            if (c.getResponseCode() != 200) throw new Exception("HTTP " + c.getResponseCode());
            InputStream in = c.getInputStream();
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) o.write(buf, 0, n);
            return o.toString("UTF-8");
        } finally {
            c.disconnect();
        }
    }
}
