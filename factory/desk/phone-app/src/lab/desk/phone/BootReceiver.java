package lab.desk.phone;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** 폰을 다시 켜도 알림 연결이 이어지게 */
public class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c, Intent i) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(i.getAction()) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(i.getAction()))
            NoticeService.start(c);
    }
}
