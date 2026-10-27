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
    /** 本次 keylayout 挂载成功时的开机时长（ms），用来判断 system_server 是不是在它之后启动的 */
    private static final String K_MOUNT_UP = "mount_uptime";
    /** 已确认 system_server 晚于挂载时刻启动（键表已生效） */
    private static final String K_CONFIRMED = "confirmed";
    /** 上次跑时的开机时长，用来识别"中间重启过" */
    private static final String K_LAST_UP = "last_uptime";

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
        // 墙钟时间在重启后是连续的，判断不了"是不是刚重启"；但 elapsedRealtime
        // （开机时长）会归零 —— 上次记的比现在还大，就说明中间重启过。
        // 重启后第一次必须真跑：2026-10-27 那次 BOOT_COMPLETED 因为距上次仅 25 秒
        // 被节流跳过，白白多等了一个巡检周期才修好。
        long up = android.os.SystemClock.elapsedRealtime();
        long lastUp = sp.getLong(K_LAST_UP, -1L);
        boolean rebooted = (lastUp < 0L) || (up < lastUp);
        if (!rebooted && now - last < MIN_GAP_MS) {
            Log.i(TAG, "[" + trigger + "] 距离上次仅 " + ((now - last) / 1000) + "s，节流跳过");
            return true;      // 不是失败，别把间隔缩回高频
        }
        sp.edit().putLong(K_LAST, now).putLong(K_LAST_UP, up).commit();

        // 1) 先看是不是已经挂好了 —— 直接读 /proc/mounts，不需要 root、不需要 adb。
        //    这样"已挂载"这个常态下完全不产生连接，只有真掉了才去连 adbd。
        int n = localMounts();
        if (n < 0) {
            String probe = MiniAdb.shell(H, P, "grep -c keylayout /proc/mounts", 5000);
            n = num(probe);
            Log.i(TAG, "[" + trigger + "] 本地读不到，退回 adb 探测 => " + probe.trim());
        }
        // 挂上 ≠ 生效：inputflinger 跑在 system_server 里，只有框架重启才会重读
        // keylayout（2026-10-27 的故障就是这个：挂载数是 2，但 system_server 从开机起
        // 没重启过，按主页键毫无反应）。
        // ⚠ 别用"我重启过没有"这种自证标志：重启框架会把本 app 一起杀掉，
        //   根本来不及落盘，于是标志永远清不掉 → 每 5 分钟重启一次框架（画面反复重载）。
        //   改成看事实：system_server 的启动时刻是不是晚于本次挂载时刻。
        boolean confirmed = sp.getBoolean(K_CONFIRMED, false);
        Log.i(TAG, "[" + trigger + "] 挂载数=" + n + "  键表已生效=" + confirmed + "  fd=" + fdCount());
        if (n >= 2 && confirmed) {
            Log.i(TAG, "已挂载且键表已生效，跳过");
            return true;
        }

        // 2) 挂载丢了 → 准备修复文件与脚本
        if (n < 2) {
            copyAsset(ctx, A);
            copyAsset(ctx, B);
            File sh = writeScript(ctx);
            Log.i(TAG, "脚本就绪：" + sh.getAbsolutePath());

            // 反复尝试：adbd 同时只认一个连接，失败多半是这个原因
            boolean mounted = false;
            for (int i = 1; i <= 8; i++) {
                String out = MiniAdb.shell(H, P, "sh " + sh.getAbsolutePath(), 6000);
                Log.i(TAG, "第 " + i + " 次尝试 => " + out.trim());
                if (out.contains("MOUNTS=2")) {
                    mounted = true;
                    break;
                }
                // 别每次都重启 adbd —— 那要 5 秒，8 轮就是 40 秒，还会把电脑上
                // 正在连着的 adb 踢掉。隔一轮重启一次，够用了。
                if (i % 2 == 0) {
                    toggleAdb();
                } else {
                    sleep(1500);
                }
            }
            if (!mounted) {
                Log.e(TAG, "自愈失败：8 次都没挂上  fd=" + fdCount());
                return false;
            }
            sp.edit().putLong(K_MOUNT_UP, android.os.SystemClock.elapsedRealtime())
                    .putBoolean(K_CONFIRMED, false).commit();
            Log.i(TAG, "keylayout 已挂载，接下来得让 system_server 在它之后重启，键表才生效");
        }

        // 3) 看事实：system_server 是不是在本次挂载之后才启动的
        long mountUp = sp.getLong(K_MOUNT_UP, -1L);
        if (mountUp < 0L) {
            // 挂载是旧版本做的、没留时刻记录。别自作主张重启框架（会白白重载一次画面），
            // 按"挂载发生在开机时刻"处理：system_server 只要在开机之后启动就算已生效。
            Log.i(TAG, "旧版挂载无时刻记录，按开机时刻处理");
            sp.edit().putLong(K_MOUNT_UP, 0L).commit();
            mountUp = 0L;
        }
        long mountSec = mountUp / 1000L;
        long ss = ssStartSec();
        if (ss > 0 && mountSec > 0 && ss > mountSec) {
            sp.edit().putBoolean(K_CONFIRMED, true).commit();
            Log.i(TAG, "system_server 启动于开机后 " + ss + "s，晚于挂载时刻 "
                    + mountSec + "s → 键表已生效");
            return true;
        }
        // 判断不了（读不到 ps / 没记录挂载时刻）就别乱重启，下一轮再说
        if (ss < 0 || mountSec < 0) {
            Log.w(TAG, "无法判定（ss=" + ss + " mountSec=" + mountSec + "），本轮不动");
            return false;
        }

        // 4) 确实还没生效 → 重启框架。bootcomplete 之前发 ctl.restart 会被 init
        //    直接忽略（开机早期那次自愈就是这么白干一场的），所以先等系统起来。
        if (!waitBootCompleted()) {
            Log.w(TAG, "系统还没 bootcomplete，推迟到下一轮再重启框架");
            return false;
        }
        if (restartFramework()) {
            Log.i(TAG, "框架已重启，下一轮确认键表生效");
            return true;
        }
        Log.e(TAG, "框架重启失败，下一轮继续");
        return false;
    }

    /**
     * system_server 的启动时刻（开机后第几秒）。
     * 取 /proc/<pid>/stat 第 22 字段 starttime（单位 clock tick，本机 USER_HZ=100）。
     * @return 秒；读不到返回 -1
     */
    private static long ssStartSec() {
        String info = ssInfo();          // pid:tick
        int i = info.indexOf(':');
        if (i < 0) {
            return -1;
        }
        try {
            return Long.parseLong(info.substring(i + 1)) / 100L;
        } catch (Throwable t) {
            return -1;
        }
    }

    /** 等系统真正起来（dev.bootcomplete=1），最多 2 分钟 */
    private static boolean waitBootCompleted() {
        for (int i = 0; i < 24; i++) {
            String v = MiniAdb.shell(H, P, "getprop dev.bootcomplete; getprop sys.boot_completed", 5000);
            if (v.trim().contains("1")) {
                return true;
            }
            sleep(5000);
        }
        return false;
    }

    /**
     * 重启 Android 框架，让 inputflinger 重新加载 keylayout。
     *
     * inputflinger 不是独立进程，它在 system_server 里（本机 `init.svc.inputflinger`
     * 为空，`ps` 也没有 inputflinger），所以只有把 system_server 干掉重来才会重读键表。
     * 两招：先客气地 `ctl.restart zygote`；不生效就直接 `kill -9 system_server`
     * （zygote 发现 system_server 死了会自杀，init 再拉起来，等于软重启）。
     *
     * @return 框架是否真的换了个 system_server（用 /proc/<pid>/stat 的 starttime 判定）
     */
    private static boolean restartFramework() {
        String before = ssInfo();
        Log.i(TAG, "重启前 system_server=" + before);
        MiniAdb.shell(H, P, "setprop ctl.restart zygote", 8000);
        if (waitRestart(before, 15)) {
            return true;
        }
        String pid = before.contains(":") ? before.substring(0, before.indexOf(':')) : "";
        if (pid.matches("\\d+")) {
            Log.w(TAG, "ctl.restart 没生效，直接 kill -9 " + pid);
            MiniAdb.shell(H, P, "kill -9 " + pid, 8000);
            return waitRestart(before, 24);
        }
        return false;
    }

    /** 轮询 system_server 的 (pid:starttime) 是否变化，每次隔 5 秒 */
    private static boolean waitRestart(String before, int tries) {
        if (before.length() == 0) {
            return false;
        }
        for (int i = 0; i < tries; i++) {
            sleep(5000);
            String now = ssInfo();
            if (now.length() > 0 && !now.equals(before)) {
                Log.i(TAG, "框架已重启：" + before + " -> " + now);
                return true;
            }
        }
        return false;
    }

    /** 取 system_server 的 `pid:starttime`，starttime 变了就说明进程换过 */
    private static String ssInfo() {
        // ⚠ 必须 grep -v grep：shell 命令行里也含 "system_server"，ps 会把 grep
        //   自己列出来，NR==1 就可能取到它 —— 而它读完就退出了，/proc/<pid>/stat
        //   已经没了，读出来是空（表现为 ss=-1，"无法判定"）。
        String out = MiniAdb.shell(H, P,
                "ps | grep system_server | grep -v grep | awk 'NR==1{print $2}'", 5000).trim();
        String pid = digits(out);
        if (pid.length() == 0) {
            return "";
        }
        String t = digits(MiniAdb.shell(H, P, "awk '{print $22}' /proc/" + pid + "/stat", 5000).trim());
        return pid + ":" + t;
    }

    private static String digits(String s) {
        if (s == null) {
            return "";
        }
        String d = s.replaceAll("[^0-9]", "");
        return d;
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
