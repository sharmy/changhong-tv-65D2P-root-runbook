package org.sharmy.chsource;

import android.app.Notification;
import android.app.Service;
import android.content.Intent;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.util.Log;

/**
 * 常驻守护：前台服务 + 每 3 分钟一次自愈。
 *
 * 为什么非要这条（2026-10-27 实测结论）：
 * 这台电视是长虹深度定制的，**禁止第三方 app 自启动**，而且拦得很彻底 ——
 *   - JobScheduler：Job 挂在那儿 overdue 也不执行（app 死了就再也不动）
 *   - AlarmManager：闹钟确实触发了（dumpsys alarm 里 1 wakeups），
 *     但 BroadcastReceiver 压根没被调用
 *   - 只有 BOOT_COMPLETED 这类开机广播能把进程拉起来，而它一次开机只来一次
 *
 * 于是形成死锁：自愈要生效必须重启框架 → 框架重启把本 app 一起杀掉 →
 * 之后再没人能拉起它 → 下次 bind mount 丢了就永久失效。
 *
 * 唯一可靠的办法就是**别让进程死**：startForeground 的优先级足够高，
 * 既躲得过 LMK，也躲得过普通后台清理；万一还是被杀了，START_STICKY 让系统重建。
 */
public class KeepAliveService extends Service {

    private static final String TAG = "ChSourceHeal";
    /** 自愈巡检周期：3 分钟。常态下只是一次本地读 /proc/mounts，开销可忽略 */
    private static final long INTERVAL_MS = 3 * 60 * 1000L;
    private static final int NOTIFY_ID = 0x65D2;

    private HandlerThread thread;
    private Handler handler;

    private final Runnable loop = new Runnable() {
        @Override
        public void run() {
            try {
                Healer.schedule(getApplicationContext());       // Job/闹钟继续挂着兜底
                Healer.run(getApplicationContext(), "keepalive");
            } catch (Throwable t) {
                Log.e(TAG, "keepalive 自愈异常", t);
            }
            if (handler != null) {
                handler.postDelayed(this, INTERVAL_MS);
            }
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        startForeground(NOTIFY_ID, buildNotification());
        thread = new HandlerThread("ch-heal");
        thread.start();
        handler = new Handler(thread.getLooper());
        handler.post(loop);
        Log.i(TAG, "常驻守护已启动，每 " + (INTERVAL_MS / 60000) + " 分钟自愈一次");
    }

    private Notification buildNotification() {
        Notification.Builder b = new Notification.Builder(this)
                .setSmallIcon(android.R.drawable.ic_menu_manage)
                .setContentTitle("信号源")
                .setContentText("主页键守护运行中")
                .setOngoing(true);
        return b.build();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // 被杀后让系统重建（前台服务实际很少被杀）
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        if (handler != null) {
            handler.removeCallbacks(loop);
        }
        if (thread != null) {
            thread.quit();
        }
        super.onDestroy();
    }
}
