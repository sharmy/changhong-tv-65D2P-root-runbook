package org.sharmy.chsource;

import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * 开机自愈：把主页键的 keylayout 修复重新装上。
 *
 * 背景：修遥控器主页键要改 /system/usr/keylayout/（key 91 -> HOME）。
 * /system 是只读 ext4 分区，root 下 remount 也被拒（Operation not permitted），
 * 只能 bind mount —— 而 bind mount 一重启就没了。
 *
 * 电视侧又没有"开机以 root 跑脚本"的入口：
 *   - /system/xbin/su 是 root:shell，第三方 app 不在 shell 组，执行不了
 *   - /system/xbin/csu 有 uid 白名单（uid 10026 not allowed）
 *   - init 的 rc 全在只读 rootfs，/etc -> /system/etc 也只读，无法挂钩子
 *   - 没有 cron，没有 install-recovery.sh
 *
 * 突破口：本机 adbd 以 root 运行且 ro.adb.secure=0（不校验 RSA），
 * 于是 app 走 127.0.0.1:5555 用 adb 协议直接拿到 root shell，
 * 全程在电视内部完成，不需要电脑、不需要 root 权限。
 *
 * 触发方式（三选一，谁能跑通都算）：
 *   1. BootReceiver 监听的一组广播（实测 BOOT_COMPLETED 被长虹拦了）
 *   2. JobScheduler 周期任务（系统持久化，开机后由系统调度 —— 兜底）
 *   3. 手动：am start -n org.sharmy.chsource/.Home --es source __HEAL__
 */
public final class Healer {

    private static final String TAG = "ChSourceHeal";
    /** 周期兜底任务（15 分钟是 API 22 允许的最小周期） */
    private static final int JOB_PERIODIC = 6510;
    /**
     * 主力任务：一次性 + 自续期。每 60~120 秒跑一次，跑完再排下一次。
     * 之所以不用纯周期任务：周期任务重启后要等一个完整周期（实测约 13 分钟）才首次执行；
     * 而一次性任务的 deadline 是"绝对时刻"，电视正常开机若干小时后其值早已过期，
     * 重启后 JobScheduler 一恢复就判定为 overdue，立刻（1~2 分钟内）执行。
     */
    private static final int JOB_NEXT = 6511;

    private static final String A = "Vendor_0001_Product_0001.kl";
    private static final String B = "Vendor_046d_Product_0002.kl";
    private static final String H = "127.0.0.1";
    private static final int P = 5555;

    /** 两次自愈之间的最小间隔，防止任务/广播风暴导致疯狂重试 */
    private static final long MIN_GAP_MS = 30 * 1000L;
    private static final String PREFS = "heal";
    private static final String K_LAST = "last_attempt";

    private Healer() {
    }

    /** 注册自愈任务：主力一次性任务 + 周期兜底任务（都持久化，重启后系统自己拉起） */
    static void schedule(Context ctx) {
        try {
            JobScheduler js = (JobScheduler) ctx.getSystemService(Context.JOB_SCHEDULER_SERVICE);
            ComponentName cn = new ComponentName(ctx, HealJobService.class);

            JobInfo next = new JobInfo.Builder(JOB_NEXT, cn)
                    .setMinimumLatency(60 * 1000L)
                    .setOverrideDeadline(120 * 1000L)
                    .setPersisted(true)
                    .build();
            int r1 = js.schedule(next);

            JobInfo periodic = new JobInfo.Builder(JOB_PERIODIC, cn)
                    .setPeriodic(15 * 60 * 1000L)
                    .setPersisted(true)
                    .setRequiresCharging(false)
                    .build();
            int r2 = js.schedule(periodic);

            Log.i(TAG, "任务已注册：JOB " + JOB_NEXT + "(60~120s 自续期)=" + r1
                    + "  JOB " + JOB_PERIODIC + "(15min 兜底)=" + r2
                    + "  注：1=成功 0=失败");
        } catch (Throwable t) {
            Log.e(TAG, "schedule 失败", t);
        }
    }

    /**
     * 排下一次（一次性任务跑完就消失，必须自己续上，否则重启后就没人拉了）。
     *
     * 间隔分两档：
     *   - 没挂上：60~120s 高频重试，尽快把主页键救回来
     *   - 已挂上：4~6min 低频巡检。bind mount 只有重启才会丢，没必要每秒盯着；
     *     降频后一小时约 12 次连接（原来 30~60 次），即便哪里再漏 fd 也撑得住。
     */
    private static void scheduleNext(Context ctx, boolean ok) {
        try {
            long min = ok ? 4 * 60 * 1000L : 60 * 1000L;
            long max = ok ? 6 * 60 * 1000L : 120 * 1000L;
            JobScheduler js = (JobScheduler) ctx.getSystemService(Context.JOB_SCHEDULER_SERVICE);
            ComponentName cn = new ComponentName(ctx, HealJobService.class);
            JobInfo next = new JobInfo.Builder(JOB_NEXT, cn)
                    .setMinimumLatency(min)
                    .setOverrideDeadline(max)
                    .setPersisted(true)
                    .build();
            js.schedule(next);
        } catch (Throwable t) {
            Log.w(TAG, "scheduleNext 失败", t);
        }
    }

    /** 执行一次自愈（同步、含等待，请在后台线程调用） */
    static void run(Context ctx, String trigger) {
        boolean ok = false;
        try {
            ok = doRun(ctx, trigger);
        } finally {
            // 一次性任务跑完就没了，必须续上下一次，否则下一次重启没人拉起
            scheduleNext(ctx, ok);
        }
    }

    /** @return true 表示 keylayout 已经挂好（或本来就挂好了） */
    private static boolean doRun(Context ctx, String trigger) {
        SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long now = System.currentTimeMillis();
        long last = sp.getLong(K_LAST, 0L);
        if (now - last < MIN_GAP_MS) {
            Log.i(TAG, "[" + trigger + "] 距离上次仅 " + ((now - last) / 1000) + "s，节流跳过");
            return true;      // 不是失败，别把间隔缩回高频
        }
        sp.edit().putLong(K_LAST, now).commit();

        // 1) 先看是不是已经挂好了 —— 直接读 /proc/mounts，不需要 root、不需要 adb。
        //    这样"已挂载"这个常态下完全不产生连接，只有真掉了才去连 adbd。
        int n = localMounts();
        if (n < 0) {
            String probe = MiniAdb.shell(H, P, "grep -c keylayout /proc/mounts", 5000);
            n = num(probe);
            Log.i(TAG, "[" + trigger + "] 本地读不到，退回 adb 探测 => " + probe.trim());
        }
        Log.i(TAG, "[" + trigger + "] 挂载数=" + n + "  fd=" + fdCount());
        if (n >= 2) {
            Log.i(TAG, "已挂载，跳过");
            return true;
        }

        // 2) 准备修复文件与脚本
        copyAsset(ctx, A);
        copyAsset(ctx, B);
        File sh = writeScript(ctx);
        Log.i(TAG, "脚本就绪：" + sh.getAbsolutePath());

        // 3) 反复尝试：adbd 同时只认一个连接，失败多半是这个原因
        for (int i = 1; i <= 8; i++) {
            String out = MiniAdb.shell(H, P, "sh " + sh.getAbsolutePath(), 6000);
            Log.i(TAG, "第 " + i + " 次尝试 => " + out.trim());
            if (out.contains("MOUNTS=2")) {
                // inputflinger 开机时已读过旧键表，必须软重启一次才生效
                MiniAdb.shell(H, P, "setprop ctl.restart zygote", 6000);
                Log.i(TAG, "keylayout 已挂载，已触发 zygote 重启（键表将重新加载）");
                return true;
            }
            // 别每次都重启 adbd —— 那要 5 秒，8 轮就是 40 秒，还会把电脑上
            // 正在连着的 adb 踢掉。隔一轮重启一次，够用了。
            if (i % 2 == 0) {
                toggleAdb();
            } else {
                sleep(1500);
            }
        }
        Log.e(TAG, "自愈失败：8 次都没挂上  fd=" + fdCount());
        return false;
    }

    /** 重启 root adbd：三行配方（长虹 init 补丁 + service.adb.root） */
    private static void toggleAdb() {
        prop("persist.service.adb.enable", "0");
        sleep(1500);
        prop("service.adb.root", "1");
        prop("persist.service.adb.enable", "1");
        sleep(3500);
    }

    private static void prop(String k, String v) {
        exec("/system/bin/setprop", k, v);
    }

    private static int num(String s) {
        if (s == null) {
            return 0;
        }
        try {
            String d = s.replaceAll("[^0-9]", "");
            return d.length() == 0 ? 0 : Integer.parseInt(d);
        } catch (Throwable t) {
            return 0;
        }
    }

    private static void exec(String... cmd) {
        Process p = null;
        try {
            p = Runtime.getRuntime().exec(cmd);
            // ⚠ Process 的 stdin/stdout/stderr 是三个 pipe fd，不关就一直占着。
            //   和 MiniAdb 的 socket 是同一个坑：app 的 fd 上限 1024，
            //   这里一次 toggleAdb 就是 3 个进程 × 3 个 fd，几小时就能耗尽。
            try { p.getOutputStream().close(); } catch (Throwable ignore) { }
            try { p.getInputStream().close(); } catch (Throwable ignore) { }
            try { p.getErrorStream().close(); } catch (Throwable ignore) { }
            p.waitFor();
        } catch (Throwable t) {
            Log.w(TAG, "exec 失败 " + cmd[0], t);
        } finally {
            if (p != null) {
                try { p.destroy(); } catch (Throwable ignore) { }
            }
        }
    }

    /**
     * 本地读 /proc/mounts 数 keylayout 的挂载条目。
     * /proc/mounts 是全局可读的，判断"修好了没有"压根用不着 root ——
     * 之前每次都为此开一条 adb 连接，纯属浪费（还白白消耗 fd）。
     * @return 挂载条数，读不了返回 -1
     */
    private static int localMounts() {
        BufferedReader r = null;
        try {
            r = new BufferedReader(new FileReader("/proc/mounts"), 4096);
            int c = 0;
            String line;
            while ((line = r.readLine()) != null) {
                if (line.contains("keylayout")) {
                    c++;
                }
            }
            return c;
        } catch (Throwable t) {
            Log.w(TAG, "读 /proc/mounts 失败", t);
            return -1;
        } finally {
            if (r != null) {
                try { r.close(); } catch (Throwable ignore) { }
            }
        }
    }

    /** 当前进程已占用的 fd 数，打进日志，方便日后一眼看出是不是又泄漏了 */
    private static int fdCount() {
        try {
            String[] l = new File("/proc/self/fd").list();
            return (l == null) ? -1 : l.length;
        } catch (Throwable t) {
            return -1;
        }
    }

    private static void copyAsset(Context ctx, String name) {
        InputStream in = null;
        OutputStream out = null;
        try {
            in = ctx.getAssets().open(name);
            File f = new File(ctx.getFilesDir(), name);
            out = new FileOutputStream(f);
            byte[] buf = new byte[8192];
            int len;
            while ((len = in.read(buf)) > 0) {
                out.write(buf, 0, len);
            }
        } catch (Throwable t) {
            Log.e(TAG, "copyAsset 失败 " + name, t);
        } finally {
            if (in != null) {
                try { in.close(); } catch (Throwable ignore) { }
            }
            if (out != null) {
                try { out.close(); } catch (Throwable ignore) { }
            }
        }
        // 让 root 能读（脚本里还要把它 cp 到 /data/chkeys）
        exec("/system/bin/chmod", "644", new File(ctx.getFilesDir(), name).getAbsolutePath());
    }

    private static File writeScript(Context ctx) {
        File f = new File(ctx.getFilesDir(), "ch_fixkeys.sh");
        FileOutputStream o = null;
        try {
            o = new FileOutputStream(f);
            String dir = ctx.getFilesDir().getAbsolutePath();
            String s = "#!/system/bin/sh\n"
                    + "mkdir -p /data/chkeys\n"
                    + "cp " + dir + "/" + A + " /data/chkeys/\n"
                    + "cp " + dir + "/" + B + " /data/chkeys/\n"
                    + "chmod 644 /data/chkeys/" + A + " /data/chkeys/" + B + "\n"
                    + "umount /system/usr/keylayout/" + A + " 2>/dev/null\n"
                    + "umount /system/usr/keylayout/" + B + " 2>/dev/null\n"
                    + "mount -o bind /data/chkeys/" + A + " /system/usr/keylayout/" + A + "\n"
                    + "mount -o bind /data/chkeys/" + B + " /system/usr/keylayout/" + B + "\n"
                    + "echo MOUNTS=$(grep -c keylayout /proc/mounts)\n";
            o.write(s.getBytes("UTF-8"));
        } catch (Throwable t) {
            Log.e(TAG, "写脚本失败", t);
        } finally {
            if (o != null) {
                try { o.close(); } catch (Throwable ignore) { }
            }
        }
        exec("/system/bin/chmod", "755", f.getAbsolutePath());
        return f;
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
