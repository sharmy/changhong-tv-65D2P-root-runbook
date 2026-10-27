package org.sharmy.chsource;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * AlarmManager 定时唤醒。
 *
 * 为什么还要这一条（已经有 JobScheduler 了）：
 * 这台电视是长虹定制的，**app 进程一旦退出，JobScheduler 到点也不会把它拉起来** ——
 * Job 就挂在那儿 overdue 不动。2026-10-27 实测：系统里有 6511 已经过期 1 分 50 秒，
 * 4 分钟里一次都没执行；手动 `am start` 把 app 拉起来后，它立刻连跑两次。
 * 所以 Job 不能单独扛，必须有别的路。
 *
 * AlarmManager 走的是"系统闹钟 → PendingIntent → 拉起目标进程"，这条路能穿透
 * （Android 5.1 没有 Doze，setRepeating 是准的）。
 */
public class AlarmReceiver extends BroadcastReceiver {

    private static final String TAG = "ChSourceHeal";

    @Override
    public void onReceive(Context ctx, Intent intent) {
        Log.i(TAG, "[alarm] 闹钟唤醒，触发自愈");
        Context app = ctx.getApplicationContext();
        Healer.schedule(app);          // Job 继续挂着当兜底
        Intent s = new Intent(app, SelfHealService.class);
        s.putExtra("trigger", "alarm");
        try {
            app.startService(s);
        } catch (Throwable t) {
            Log.w(TAG, "[alarm] startService 失败", t);
        }
    }
}
