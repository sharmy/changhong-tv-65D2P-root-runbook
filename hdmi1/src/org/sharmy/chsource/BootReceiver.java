package org.sharmy.chsource;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * 触发自愈：把主页键的 keylayout 修复重新装上（bind mount 一重启就失效）。
 *
 * 实测：长虹会拦第三方 app 的 BOOT_COMPLETED（进程根本拉不起来），
 * 所以这里同时监听多个"开机前后必定发生"的广播，哪个能用算哪个；
 * 真正的兜底是 JobScheduler（见 Healer.schedule）。
 *
 * ⚠️ 包名必须在 /chperm/preapp/keeprunning 里（电视管家 → 权限管理 →
 *    自动启动管理 / 后台运行），否则进程会被 system_server 的 keepkilling 杀掉。
 */
public class BootReceiver extends BroadcastReceiver {

    private static final String TAG = "ChSourceBoot";

    @Override
    public void onReceive(Context ctx, Intent intent) {
        String a = intent == null ? "(null)" : intent.getAction();
        Log.i(TAG, "收到 " + a);
        Context app = ctx.getApplicationContext();

        // 不管这次广播是哪来的，都顺手把周期任务注册上（幂等）
        Healer.schedule(app);

        // 拉起常驻守护。这是最要紧的一步：这台电视上进程一旦退出就再也拉不回来
        // （Job/闹钟都不行），所以每次抓到广播都顺手把它叫起来。
        try {
            app.startService(new Intent(app, KeepAliveService.class));
        } catch (Throwable t) {
            Log.e(TAG, "启动 KeepAliveService 失败", t);
        }

        try {
            Intent svc = new Intent(app, SelfHealService.class);
            svc.putExtra("trigger", a);
            app.startService(svc);
        } catch (Throwable t) {
            Log.e(TAG, "启动 SelfHealService 失败", t);
        }
    }
}
