package org.sharmy.chsource;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.lang.reflect.Method;

/**
 * 「回到安卓系统桌面」的统一实现，Activity 和常驻 Service 共用。
 *
 * 实测结论（别再走弯路）：
 *  1. 只发 HOME intent 不够 —— 桌面确实到了前台，但底层视频层还在输出 HDMI，
 *     画面被盖住，看起来就像没反应；必须让 TV 播放器进程释放资源。
 *  2. ITVPlayer.stop() 对第三方 app 恒为 false（TVServiceHandler 首行
 *     checkClientResource(调用方pid) 就 return），只能"尽力而为"。
 *  3. 真正有效的是：先 HOME 把播放器挤到后台，再 killBackgroundProcesses
 *     杀掉 com.changhong.tvap.atv.activity，TVServiceHandler 才会
 *     onClientDied → 停掉底层 HDMI 输出，桌面画面才露出来。
 *  4. 前提是 Settings.Secure.user_setup_complete=1，否则系统拒绝启动桌面
 *     （见 runbook §3.7.1）。
 */
public final class HomeUtil {

    private static final String TAG = "ChSourceSwitch";
    public static final String TV_PLAYER_PKG = "com.changhong.tvap.atv.activity";
    private static final String C_TV_MANAGER = "com.changhong.tvos.common.TVManager";
    private static final String C_ITV_PLAYER = "com.changhong.tvos.common.ITVPlayer";

    private HomeUtil() {
    }

    /** 回到系统桌面；stopVideo=true 时先尽力调一次 ITVPlayer.stop() */
    public static String goHome(final Context ctx, boolean stopVideo) {
        final StringBuilder d = new StringBuilder();
        String cur = "";

        if (stopVideo) {
            try {
                Object tv = Class.forName(C_TV_MANAGER)
                        .getMethod("getInstance", Context.class)
                        .invoke(null, ctx.getApplicationContext());
                Object player = tv.getClass().getMethod("getATVPlayer").invoke(tv);
                Object rc = Class.forName(C_ITV_PLAYER).getMethod("stop").invoke(player);
                d.append("stop=").append(rc).append(" ");
            } catch (Throwable t) {
                Log.w(TAG, "ITVPlayer.stop 失败", t);
                d.append("stop:").append(t.getClass().getSimpleName()).append(" ");
            }
        }

        // 先拉桌面到前台，让 TV 播放器变成后台进程
        try {
            Intent home = new Intent(Intent.ACTION_MAIN);
            home.addCategory(Intent.CATEGORY_HOME);
            home.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                    | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            ctx.startActivity(home);
            d.append("home:ok ");
        } catch (Throwable t) {
            Log.e(TAG, "HOME intent 失败", t);
            d.append("home:").append(t.getClass().getSimpleName()).append(" ");
        }

        // 再杀后台的 TV 播放器，释放底层视频资源
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override
            public void run() {
                try {
                    ActivityManager am =
                            (ActivityManager) ctx.getSystemService(Context.ACTIVITY_SERVICE);
                    am.killBackgroundProcesses(TV_PLAYER_PKG);
                    Log.i(TAG, "killBackgroundProcesses(" + TV_PLAYER_PKG + ") 已调用");
                } catch (Throwable t) {
                    Log.e(TAG, "killBackgroundProcesses 失败", t);
                }
            }
        }, 600);

        return "已回到系统桌面 " + d + (cur.length() > 0 ? "源=" + cur : "");
    }
}
