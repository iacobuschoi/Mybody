package lab.desk.phone;

import android.content.Context;

import java.net.InterfaceAddress;
import java.net.NetworkInterface;
import java.util.Collections;

/** 앱 안의 Tailscale(deskts) — 화면(MainActivity)과 알림 서비스(NoticeService)가 같이 씀. 한 번만 뜸 */
final class Net {
    private static String base;

    /** http://127.0.0.1:<프록시> — 테일넷으로 맥에 닿음 */
    static synchronized String base(Context c) throws Exception {
        if (base == null) {
            deskts.Deskts.setInterfaces(interfaces());
            long port = deskts.Deskts.start(c.getFilesDir() + "/tailscale", "desk-phone", Secrets.TARGET);
            base = "http://127.0.0.1:" + port;
        }
        return base;
    }

    static void refresh() { deskts.Deskts.setInterfaces(interfaces()); }

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
}
