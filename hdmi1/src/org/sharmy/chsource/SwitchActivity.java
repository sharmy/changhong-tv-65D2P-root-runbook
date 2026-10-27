package org.sharmy.chsource;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.util.Log;
import android.widget.Toast;

import java.lang.reflect.Method;

/**
 * 长虹 65D2P（ZLH74GiR / Android 5.1.1）信号源一键切换。
 *
 * 原理：系统把 /system/framework/com.changhong.tvos.jar 放进了 BOOTCLASSPATH，
 * 因此任意 app 都能反射调用长虹私有 TVOS SDK：
 *     TVManager.getInstance(ctx).getATVPlayer()
 *         .startInputSource(EnumInputSource.E_INPUT_SOURCE_HDMI, 15)
 * 这正是系统「信号源」菜单（com.changhong.SourceMenu → MenuSource.changeSource）
 * 内部使用的同一条调用链。
 *
 * 切到哪个源由 activity-alias 的 <meta-data android:name="source"> 决定。
 * 注：切换会写 Settings.System，需要 WRITE_SETTINGS 权限（root 下用 pm grant 授予）。
 */
public class SwitchActivity extends Activity {

    private static final String TAG = "ChSourceSwitch";
    public static final String META_SOURCE = "source";

    private static final String C_TV_MANAGER = "com.changhong.tvos.common.TVManager";
    /** 持有 TV 播放资源的系统播放器进程，切源后由它显示 HDMI/DTV 画面 */
    private static final String TV_PLAYER_PKG = "com.changhong.tvap.atv.activity";
    private static final String C_ITV_PLAYER = "com.changhong.tvos.common.ITVPlayer";
    private static final String C_ISRC_MGR   = "com.changhong.tvos.common.ISourceManager";
    private static final String C_ENUM_SRC   = "com.changhong.tvos.model.EnumInputSource";
    private static final String C_ENUM_PIP   = "com.changhong.tvos.model.ChOsType$EnumPipInputSource";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // 每次打开本 app 都确保「自愈周期任务」已注册（JobScheduler 会持久化，
        // 开机后由系统自己拉起 —— 长虹会拦第三方 app 的 BOOT_COMPLETED，
        // 广播靠不住，只能靠系统调度器兜底）
        Healer.schedule(getApplicationContext());
        // 顺手把常驻守护叫起来（用户点过一次图标之后就不用再操心它了）
        try {
            startService(new Intent(this, KeepAliveService.class));
        } catch (Throwable ignore) {
        }

        String src = "E_INPUT_SOURCE_HDMI";
        // adb 调试用：am start -n org.sharmy.chsource/.Hdmi1 --es source __LIST__
        String fromIntent = getIntent() == null ? null : getIntent().getStringExtra(META_SOURCE);
        if (fromIntent != null && fromIntent.length() > 0) {
            src = fromIntent;
        } else {
            try {
                ActivityInfo ai = getPackageManager()
                        .getActivityInfo(getComponentName(), PackageManager.GET_META_DATA);
                if (ai != null && ai.metaData != null) {
                    String s = ai.metaData.getString(META_SOURCE);
                    if (s != null && s.length() > 0) {
                        src = s;
                    }
                }
            } catch (Throwable t) {
                Log.w(TAG, "read meta-data failed", t);
            }
        }

        String msg;
        if ("__MENU__".equals(src)) {
            msg = openSourceMenu();
        } else if ("__HOME__".equals(src)) {
            msg = goHome(false);
        } else if ("__SYS__".equals(src)) {
            msg = goHome(true);
        } else if ("__ADB__".equals(src)) {
            // 调试：验证 app 能否连本机 root adbd 执行命令（--es cmd "id"）
            final String c = getIntent().getStringExtra("cmd") == null
                    ? "id" : getIntent().getStringExtra("cmd");
            new Thread(new Runnable() {
                @Override
                public void run() {
                    String h = getIntent().getStringExtra("host");
                    if (h == null || h.length() == 0) { h = "127.0.0.1"; }
                    final String r = MiniAdb.shell(h, 5555, c, 5000);
                    Log.i(TAG, "adb(" + c + ") => " + r);
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            Toast.makeText(getApplicationContext(), r, Toast.LENGTH_LONG).show();
                        }
                    });
                }
            }).start();
            msg = "adb 执行中，结果见 logcat / Toast";
        } else if ("__HEAL__".equals(src)) {
            // 手动触发一次开机自愈（不重启电视也能验证）
            startService(new android.content.Intent(this, SelfHealService.class));
            msg = "自愈已触发，看 logcat ChSourceHeal";
        } else {
            msg = switchTo(getApplicationContext(), src);
        }
        Log.i(TAG, msg);
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show();

        getWindow().getDecorView().postDelayed(new Runnable() {
            @Override
            public void run() {
                finish();
            }
        }, 2200);
    }

    /**
     * 从 HDMI / DTV 回到安卓系统桌面。
     *
     * 关键（实测踩坑）：只发 HOME intent 是不够的 —— 桌面确实会被调到前台
     * （mCurrentFocus 变成 com.dangbei.tvlauncher），但底层视频层仍在输出 HDMI，
     * 画面被盖住，看起来就像"主页键没反应"。
     * 必须先 ITVPlayer.stop() 让 Tvmain 停掉视频输出，再拉起桌面。
     *
     * @param stopVideo true=先 stop() 停视频层（推荐），false=只发 HOME（对照用）
     */
    private String goHome(boolean stopVideo) {
        return HomeUtil.goHome(getApplicationContext(), stopVideo);
    }

    /** 旧实现，仅留作对照，不再调用 */
    private String goHomeLegacyUnused(boolean stopVideo) {
        StringBuilder d = new StringBuilder();
        String cur = "";
        if (stopVideo) {
            // (a) TVOS 侧：我们自己这个 client 未必持有资源，stop() 常常返回 false，仅尽力而为
            try {
                Object tv = Class.forName(C_TV_MANAGER)
                        .getMethod("getInstance", Context.class)
                        .invoke(null, getApplicationContext());
                Object player = tv.getClass().getMethod("getATVPlayer").invoke(tv);
                Object rc = Class.forName(C_ITV_PLAYER).getMethod("stop").invoke(player);
                d.append("stop=").append(rc).append(" ");
                try {
                    cur = pretty(currentSource(tv));
                } catch (Throwable ignore) {
                }
            } catch (Throwable t) {
                Log.w(TAG, "ITVPlayer.stop 失败", t);
                d.append("stop:").append(shortErr(t)).append(" ");
            }
        }

        // (b) 先把桌面拉到前台 —— 这样 TV 播放器（AtvMainActivity）变成「后台进程」，
        //     下一步才有权杀它（killBackgroundProcesses 只杀后台进程）
        try {
            android.content.Intent home = new android.content.Intent(android.content.Intent.ACTION_MAIN);
            home.addCategory(android.content.Intent.CATEGORY_HOME);
            home.setFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                    | android.content.Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            startActivity(home);
            d.append("home:ok ");
        } catch (Throwable t) {
            Log.e(TAG, "HOME intent 失败", t);
            d.append("home:").append(shortErr(t)).append(" ");
        }

        // (c) 关键一步：杀掉 TV 播放器进程。
        //     它持有 TVOS 的播放资源（checkClientResource 就是按 pid 判的），
        //     只有它死了，TVServiceHandler 才会 onClientDied → 释放资源 → 底层停掉 HDMI 输出，
        //     安卓桌面的画面才露得出来。
        //     延时一点，等 ActivityManager 真的把它置为后台。
        getWindow().getDecorView().postDelayed(new Runnable() {
            @Override
            public void run() {
                try {
                    android.app.ActivityManager am =
                            (android.app.ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
                    am.killBackgroundProcesses(TV_PLAYER_PKG);
                    Log.i(TAG, "killBackgroundProcesses(" + TV_PLAYER_PKG + ") 已调用");
                } catch (Throwable t) {
                    Log.e(TAG, "killBackgroundProcesses 失败", t);
                }
            }
        }, 600);

        return "已回到系统桌面 " + d + (cur.length() > 0 ? "源=" + cur : "");
    }

    /** 弹出系统原生「信号源」菜单（SourceMenuService 的 menuSource 指令） */
    private String openSourceMenu() {
        try {
            android.content.Intent i = new android.content.Intent("CH_MENU_SOURCE");
            i.setClassName("com.changhong.SourceMenu", "com.changhong.source.SourceMenuService");
            i.putExtra("MenuSource", "menuSource");
            i.putExtra("keyCode", 2001);
            startService(i);
            return "已打开信号源菜单";
        } catch (Throwable t) {
            Log.e(TAG, "openSourceMenu failed", t);
            return "打开失败：" + shortErr(t);
        }
    }

    static String switchTo(Context ctx, String enumName) {
        StringBuilder detail = new StringBuilder();
        try {
            Object tvManager = Class.forName(C_TV_MANAGER)
                    .getMethod("getInstance", Context.class).invoke(null, ctx);
            if (tvManager == null) {
                return "TVManager 未初始化";
            }

            // 诊断：列出本机支持的信号源
            if ("__LIST__".equals(enumName)) {
                return "支持：" + supportedList(tvManager)
                        + " 当前：" + pretty(currentSource(tvManager));
            }

            Class<?> enumCls = Class.forName(C_ENUM_SRC);
            Object target = null;
            for (Object v : (Object[]) enumCls.getMethod("values").invoke(null)) {
                if (enumName.equals(((Enum<?>) v).name())) {
                    target = v;
                    break;
                }
            }
            if (target == null) {
                return "未知信号源 " + enumName;
            }

            // 路径 A：与系统信号源菜单完全一致（startInputSource）
            boolean aOk = false;
            try {
                Object player = tvManager.getClass().getMethod("getATVPlayer").invoke(tvManager);
                Method m = Class.forName(C_ITV_PLAYER)
                        .getMethod("startInputSource", enumCls, int.class);
                Object rc = m.invoke(player, target, 15);
                detail.append("A:ok(").append(rc).append(") ");
                aOk = true;
            } catch (Throwable t) {
                detail.append("A:").append(shortErr(t)).append(" ");
                Log.w(TAG, "startInputSource 异常", t);
            }

            // 路径 B：仅当 A 失败时才补一次 ISourceManager.selectInputSource
            if (!aOk) {
                try {
                    Object srcMgr = tvManager.getClass().getMethod("getSourceManager").invoke(tvManager);
                    Method m2 = Class.forName(C_ISRC_MGR).getMethod("selectInputSource", enumCls);
                    Object rc2 = m2.invoke(srcMgr, target);
                    detail.append("B:ok(").append(rc2).append(") ");
                } catch (Throwable t) {
                    detail.append("B:").append(shortErr(t)).append(" ");
                    Log.w(TAG, "selectInputSource 异常", t);
                }
            }

            // 以「当前实际信号源」为准判定结果
            String now = currentSource(tvManager);
            if (enumName.equals(now)) {
                return "已切换到 " + pretty(enumName);
            }
            return "切换未生效（当前=" + pretty(now) + " 目标=" + pretty(enumName) + "） " + detail;
        } catch (Throwable t) {
            Log.e(TAG, "switchTo(" + enumName + ") failed", t);
            return "切换失败：" + shortErr(t);
        }
    }

    /** 读回当前主画面信号源名（失败返回 ""） */
    private static String currentSource(Object tvManager) {
        try {
            Class<?> enumCls = Class.forName(C_ENUM_SRC);
            Class<?> pipCls = Class.forName(C_ENUM_PIP);
            Object main = null;
            for (Object v : (Object[]) pipCls.getMethod("values").invoke(null)) {
                if ("E_MAIN_INPUT_SOURCE".equals(((Enum<?>) v).name())) {
                    main = v;
                    break;
                }
            }
            Object srcMgr = tvManager.getClass().getMethod("getSourceManager").invoke(tvManager);
            Method m = Class.forName(C_ISRC_MGR).getMethod("getCurInputSource", pipCls);
            Object cur = m.invoke(srcMgr, main);
            return cur == null ? "" : ((Enum<?>) cur).name();
        } catch (Throwable t) {
            Log.w(TAG, "getCurInputSource 失败", t);
            return "";
        }
    }

    private static String supportedList(Object tvManager) {
        try {
            Object srcMgr = tvManager.getClass().getMethod("getSourceManager").invoke(tvManager);
            Object list = Class.forName(C_ISRC_MGR).getMethod("getInputSourceList").invoke(srcMgr);
            StringBuilder sb = new StringBuilder();
            for (Object v : (java.util.List<?>) list) {
                if (sb.length() > 0) {
                    sb.append(",");
                }
                sb.append(pretty(((Enum<?>) v).name()));
            }
            return sb.toString();
        } catch (Throwable t) {
            Log.w(TAG, "getInputSourceList 失败", t);
            return shortErr(t);
        }
    }

    private static String shortErr(Throwable t) {
        Throwable r = t;
        while (r.getCause() != null) {
            r = r.getCause();
        }
        String s = r.getClass().getSimpleName();
        if (r.getMessage() != null) {
            s += ": " + r.getMessage();
        }
        return s;
    }

    private static String pretty(String n) {
        if (n == null) {
            return "?";
        }
        if (n.startsWith("E_INPUT_SOURCE_")) {
            String s = n.substring("E_INPUT_SOURCE_".length());
            if (s.equals("HDMI")) {
                return "HDMI1";
            }
            if (s.startsWith("HDMI") && s.length() == 5) {
                return "HDMI" + s.substring(4);
            }
            return s;
        }
        return n;
    }
}
