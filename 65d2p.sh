#!/bin/bash
# ============================================================
# 长虹 65D2P（机芯 ZLH74GiR / V1.00039 / Android 5.1.1）维护脚本
# 用法： ./65d2p.sh <子命令>
#   status       查看状态（root / ADB / 禁用数 / 当前桌面）
#   ota-lock     封死 OTA（禁用 4 个升级组件）
#   adblock      禁用 10 个广告/推送/预装游戏包
#   lock-all     = ota-lock + adblock（一键全做）
#   restore      全部恢复（撤销 lock-all）
#   switch-home  切换到当贝桌面（需先装好 com.dangbei.tvlauncher）
#   restore-home 恢复长虹原生桌面
#   install <apk>  推送安装 APK
#   replace-db <apk> 替换当贝桌面（清残留+装纯净版+锁开机直达）
#   lock-db-bootad 锁定当贝桌面"开机直达"广告开关（switch_on=0 + immutable）
#   pkgs        列出第三方应用 / 已禁用应用
#   shell <cmd> 在电视上执行任意命令（root 身份）
#   fix-adb     ADB 失联急救：经 SimpleSSHD(2222免密ssh) 三行配方拉起 root adbd
#   fix-home    修「切到 HDMI/DTV 后按主页键没反应」（user_setup_complete=0 导致系统拒绝启动桌面）
#   home-apk    装信号源一键切换 APK（HDMI1/HDMI2/DTV/AV/回系统桌面/信号源菜单）
# ============================================================

TV="192.168.1.2:5555"
SSH_PORT=2222
SSH_KEY="$(dirname "$0")/tvkey"   # SimpleSSHD 免密私钥（authorized_keys 已写入电视）

# ---- 定位 adb ----
if [ -n "$ADB_BIN" ] && [ -x "$ADB_BIN" ]; then
  ADB="$ADB_BIN"
elif command -v adb >/dev/null 2>&1; then
  ADB="$(command -v adb)"
elif [ -x /tmp/pt/platform-tools/adb ]; then
  ADB="/tmp/pt/platform-tools/adb"
else
  echo "❌ 找不到 adb。下载方式："
  echo "   cd /tmp && curl -sL -o pt.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip && unzip -q pt.zip -d /tmp/pt"
  exit 1
fi

# ---- 在电视上以 root 执行命令（绕过长虹定制 login 密码）----
# 注意：裸 `adb shell` 会要求密码且常见密码全错，必须用 exec-out / -- 
tv() { $ADB exec-out sh -c "$1" 2>&1; }

ensure_conn() {
  if ! $ADB devices 2>/dev/null | grep -q "$TV"; then
    echo "▸ 连接 $TV ..."
    $ADB connect "$TV" >/dev/null 2>&1
    sleep 1
  fi
  $ADB devices 2>/dev/null | grep -q "$TV" || { echo "❌ 连不上 $TV"; exit 1; }
}

# ---- 包清单 ----
AD_PKGS="com.changhong.chchoujiangfortv com.changhong.chhongbaofortv com.changhong.spanner \
com.changhong.chrecommendersystem com.changhong.pointstore com.changhong.chnoticesystem \
com.changhong.inspection com.changhong.remoteassistance com.egame.tv com.tencent.tvgamehall \
com.changhong.huan.logo.service tv.huan.recognizecoreV551"

OTA_PKGS="com.changhong.systemupgrade com.changhong.dmt.upgrade com.changhong.upgrade com.changhong.upgradechiq"

CH_LAUNCHER="com.changhong.system.launcher.v2"
DB_LAUNCHER="com.dangbei.tvlauncher"

disable_pkgs() {
  for p in $1; do
    printf "  ▸ 禁用 %-45s " "$p"
    tv "pm disable $p" >/dev/null 2>&1 && echo "OK" || echo "跳过/不存在"
  done
}

enable_pkgs() {
  for p in $1; do
    printf "  ▸ 恢复 %-45s " "$p"
    tv "pm enable $p" >/dev/null 2>&1 && echo "OK" || echo "跳过/不存在"
  done
}

case "$1" in
  status)
    ensure_conn
    echo "=== 身份 ===";      tv "id"
    echo "=== 系统 ===";      tv "getprop ro.build.display.id; getprop ro.build.version.release"
    echo "=== ADB ===";       tv "getprop service.adb.tcp.port; getprop persist.adb.tcp.port; getprop ro.adb.secure"
    echo "=== 已禁用 $(tv "pm list packages -d" | grep -c 'package:') 个 ==="
    echo "=== 当前桌面 ===";  tv "dumpsys window windows | /system/bin/busybox grep mCurrentFocus"
    echo "=== 空间 ===";      tv "df /data | /system/bin/busybox tail -1"
    ;;

  ota-lock)
    ensure_conn
    echo "=== 封死 OTA ==="
    disable_pkgs "$OTA_PKGS"
    ;;

  adblock)
    ensure_conn
    echo "=== 禁用广告/推送 ==="
    disable_pkgs "$AD_PKGS"
    ;;

  lock-all)
    ensure_conn
    echo "=== 封死 OTA ==="; disable_pkgs "$OTA_PKGS"
    echo "=== 禁用广告 ==="; disable_pkgs "$AD_PKGS"
    echo "✅ 完成，共禁用 $(tv "pm list packages -d" | grep -c 'package:') 个"
    ;;

  restore)
    ensure_conn
    echo "=== 恢复所有被禁用的包 ==="
    enable_pkgs "$AD_PKGS"
    enable_pkgs "$OTA_PKGS"
    echo "✅ 剩余禁用 $(tv "pm list packages -d" | grep -c 'package:') 个"
    ;;

  switch-home)
    ensure_conn
    if ! tv "pm list packages" | grep -q "$DB_LAUNCHER"; then
      echo "❌ 当贝桌面未安装。先在电视当贝市场装「当贝桌面」，或： $0 install <当贝桌面.apk>"
      exit 1
    fi
    echo "▸ 切到当贝桌面"; tv "am start -a android.intent.action.MAIN -c android.intent.category.HOME" >/dev/null
    sleep 2
    echo "▸ 禁用长虹桌面"; tv "pm disable $CH_LAUNCHER"
    sleep 2
    echo "▸ 验证："; tv "dumpsys window windows | /system/bin/busybox grep mCurrentFocus"
    ;;

  restore-home)
    ensure_conn
    echo "▸ 恢复长虹桌面"; tv "pm enable $CH_LAUNCHER"
    tv "am start -a android.intent.action.MAIN -c android.intent.category.HOME" >/dev/null
    ;;

  install)
    ensure_conn
    [ -z "$2" ] && { echo "用法：$0 install <apk路径>"; exit 1; }
    echo "▸ 安装 $2"; $ADB install -r "$2" 2>&1 | tail -3
    ;;

  lock-db-bootad)
    ensure_conn
    D=/data/data/com.dangbei.tvlauncher/shared_prefs/share_data.xml
    BH=/system/bin/busybox
    UID_NUM="$(tv "$BH grep '^com.dangbei.tvlauncher ' /data/system/packages.list" | awk '{print $2}')"
    [ -z "$UID_NUM" ] && { echo "❌ 当贝桌面未安装"; exit 1; }
    echo "▸ 当贝 uid=$UID_NUM，改 switch_on=1 → 0"
    tv "$BH chattr -i $D 2>/dev/null"
    tv "$BH sed -i 's/switch_on&quot;:1/switch_on\&quot;:0/g' $D 2>/dev/null || $BH sed -i 's/switch_on\":1/switch_on\":0/g' $D"
    tv "$BH chown $UID_NUM:$UID_NUM $D; $BH chmod 660 $D; $BH chattr +i $D"
    echo "▸ 结果：$(tv "$BH grep -o 'switch_on[^,]*' $D") | $(tv "$BH lsattr $D")"
    echo "   （含 i 标志=已锁定；switch 0=已关）"
    ;;

  replace-db)
    ensure_conn
    [ -z "$2" ] && { echo "用法：$0 replace-db <当贝桌面纯净版.apk>"; exit 1; }
    [ -f "$2" ] || { echo "❌ 文件不存在：$2"; exit 1; }
    echo "▸ 1/5 恢复长虹桌面做安全网"
    tv "pm enable com.changhong.system.launcher.v2" >/dev/null 2>&1
    echo "▸ 2/5 卸载旧当贝（清数据）"
    tv "pm uninstall com.dangbei.tvlauncher" 2>&1
    echo "▸ 3/5 清残留（含 chattr -i 解锁 share_data.xml）"
    tv "/system/bin/busybox chattr -R -i /data/data/com.dangbei.tvlauncher 2>/dev/null; /system/bin/busybox rm -rf /data/data/com.dangbei.tvlauncher"
    echo "▸ 4/5 安装新包"
    $ADB install -r "$2" 2>&1 | tail -2
    echo "▸ 5/5 锁开机直达广告"
    "$0" lock-db-bootad
    echo "✅ 完成。首次启动需在电视上同意协议并选「精美壁纸」"
    ;;

  pkgs)
    ensure_conn
    echo "=== 第三方 ==="; tv "pm list packages -3" | sed 's/package:/  /'
    echo "=== 已禁用 ==="; tv "pm list packages -d" | sed 's/package:/  /'
    ;;

  shell)
    ensure_conn
    shift; tv "$*"
    ;;

  fix-adb)
    # 适用场景：重启电视后 5555 拒连 / exec-out 狂弹 Password（adbd 以 shell 身份运行）
    # 原理（2026-10-18 实战验证）：
    #   1. Changhong init 补丁: persist.service.adb.enable=1 → start adbd（=0 → stop）
    #      且该属性 app 权限即可设置（但开机会被系统重置，不能指望自愈）
    #   2. service.adb.root=1 让 adbd 以 root 启动（绕过密码门），同样 app 权限可设
    #   3. SimpleSSHD 已设 onboot=true 开机自启，ssh 免密（公钥已固化）
    TVIP="${TV%%:*}"
    [ -f "$SSH_KEY" ] || { echo "❌ 缺少私钥 $SSH_KEY"; exit 1; }
    sshfix() {
      ssh -p "$SSH_PORT" -i "$SSH_KEY" \
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=8 "admin@${TVIP}" "$1" 2>/dev/null
    }
    sshfix "id" >/dev/null || { echo "❌ ssh 不通：电视上手动打开 SimpleSSHD 再试（或等开机自启）"; exit 1; }
    echo "▸ 经 SimpleSSHD($SSH_PORT) 执行三行配方 ..."
    sshfix "setprop persist.service.adb.enable 0"      # 停 adbd（触发 init stop）
    sleep 2
    sshfix "setprop service.adb.root 1"                # root 标志（下次启动生效）
    sleep 1
    sshfix "setprop persist.service.adb.enable 1"      # 起 adbd → 以 root 运行
    sleep 3
    echo "▸ 验证 ..."
    $ADB disconnect >/dev/null 2>&1
    $ADB connect "$TV" >/dev/null 2>&1
    sleep 1
    $ADB -s "$TV" exec-out id >/tmp/_65d2p_id 2>/dev/null &
    _P=$!; ( sleep 6; kill $_P 2>/dev/null ) & _W=$!
    wait $_P 2>/dev/null; kill $_W 2>/dev/null
    if grep -q "uid=0" /tmp/_65d2p_id 2>/dev/null; then
      echo "✅ root adb 已恢复（$TV）"
      echo "▸ 顺带恢复广告 hosts 拦截（bind mount 重启会失效）"
      "$0" hosts-lock 2>/dev/null | sed 's/^/   /'
    else
      echo "⚠️ 未恢复，检查电视端 SimpleSSHD 是否在运行、或再跑一次本命令"
      exit 1
    fi
    ;;

  hosts-lock)
    ensure_conn
    # /system 是只读 ext4（remount,rw 报 Operation not permitted），改不了 /system/etc/hosts。
    # 绕过办法：把 /data 上可写的 hosts bind mount 覆盖到 /system/etc/hosts（root 可行）。
    # 局限：bind mount 重启失效 → 已并入 fix-adb，每次开机跑一次即可。
    BH=/system/bin/busybox
    H="$(dirname "$0")/hosts_block"
    [ -f "$H" ] || H=/tmp/dbimg/hosts_block
    if [ ! -f "$H" ]; then
      echo "❌ 找不到 hosts_block 黑名单文件（放脚本同目录或 /tmp/dbimg/）"; exit 1
    fi
    $ADB -s "$TV" push "$H" /data/local/tmp/hosts >/dev/null 2>&1
    tv "chmod 644 /data/local/tmp/hosts"
    tv "umount /system/etc/hosts 2>/dev/null; mount -o bind /data/local/tmp/hosts /system/etc/hosts 2>&1"
    echo "▸ 生效中的 hosts（前 3 行）："
    tv "cat /system/etc/hosts | $BH head -3" | sed 's/^/   /'
    N=$(tv "cat /system/etc/hosts | $BH grep -c '^127.0.0.1'" | tr -dc '0-9')
    echo "✅ 已拦截 ${N:-?} 个域名（含 localhost）"
    echo "   验证：重启当贝后 logcat 应见 ECONNREFUSED 到 127.0.0.1"
    ;;

  hosts-unlock)
    ensure_conn
    tv "umount /system/etc/hosts 2>&1"
    echo "▸ 已还原系统原 hosts："; tv "cat /system/etc/hosts"
    ;;

  kill-iqiyi-bootad)
    # 爱奇艺TV版(com.gitvdemo.video) Cupid 开机屏广告：15秒视频，素材本地缓存 → 不联网也能播，
    # 所以"开机即播、进系统前已放完"，hosts 单独拦不住。三层处置，前两层持久化（重启保留）：
    #   1) pm disable QYBootCompleteReceiver   → 开机不再拉起（持久）
    #   2) 删缓存素材 + 广告配置文件占位 chattr +i → 没素材可播、也写不回去（持久）
    #   3) hosts 封 *.cupid.ptqy.gitv.tv / data.video.ptqy.gitv.tv（重启失效，靠前两层兜底）
    ensure_conn
    BH=/system/bin/busybox
    D=/data/data/com.gitvdemo.video
    echo "▸ 1/3 禁用开机自启接收器（持久）"
    tv "pm disable com.gitvdemo.video/com.gala.video.app.boot.autoboot.QYBootCompleteReceiver" 2>&1
    tv "am force-stop com.gitvdemo.video"
    echo "▸ 2/3 清缓存素材（先解锁再删，保证可重复执行）"
    tv "for F in cupidBootScreenResponse marketing_dynamic DynamicCache; do $BH chattr -i $D/files/\$F 2>/dev/null; done"
    tv "$BH rm -f $D/files/cupidBootScreenResponse $D/files/marketing_dynamic $D/files/DynamicCache $D/files/MMKV_DiskCache"
    tv "find $D -maxdepth 1 -type f -size +400k -name '[0-9a-f]*' -exec rm -f {} \; 2>/dev/null"
    echo "▸ 3/3 占位锁死广告配置文件（持久，阻止重新下载写入）"
    tv "for F in cupidBootScreenResponse marketing_dynamic DynamicCache; do \
          P=$D/files/\$F; $BH touch \$P; $BH chown 10027:10027 \$P; $BH chmod 600 \$P; $BH chattr +i \$P; \
        done"
    echo "▸ 结果："
    tv "$BH lsattr $D/files/cupidBootScreenResponse; $BH ls -la $D/files/cupidBootScreenResponse" | sed 's/^/   /'
    echo "✅ 完成（含 i 标志=已锁死，0字节=无广告配置）"
    ;;

  kill-bootlogo-ad)
    # ⭐ 开机广告终极真凶：长虹 bootanimation(native) 读 /data/logo/config/huanlogo →
    #    播放 /data/logo/media4/video.ts（KJGG=开机广告，从 adsboot-cdn.cedock.com 下载缓存）
    #    断网也能播（本地文件）、在当贝桌面之前播（bootanimation 阶段），故 hosts 无效、禁 app 也无效。
    # 处置全部落在 /data（可写）且 chattr +i 锁死 → 持久，不依赖开机执行：
    #   1) huanlogo.isOpen true→false   2) adInfo → []   3) video.ts → 0 字节
    #   4) persist.sys.logo.time=0      5) third.bootanimation.close=1
    ensure_conn
    BH=/system/bin/busybox
    NAS=/data/local/tmp/logo_backup
    echo "▸ 0/4 备份原文件 → $NAS（已存在则跳过，避免覆盖原始备份）"
    tv "mkdir -p $NAS; \
        for F in /data/logo/config/huanlogo /data/logo/media4/adInfo /data/logo/media4/video.ts; do \
          B=$NAS/\$(basename \$F).bak; [ -f \$B ] || cp \$F \$B; \
        done; ls -la $NAS" | sed 's/^/   /'
    TMP=$(mktemp -d)
    printf '%s' '{"isOpen":"false","adServer":"http://ads.huan.tv/a.gif","materialPath":"/data/logo/media4","dologo":"dologo"}' > "$TMP/huanlogo_new"
    printf '%s' '[]' > "$TMP/adInfo_new"
    : > "$TMP/video_empty"
    $ADB -s "$TV" push "$TMP/huanlogo_new" /data/local/tmp/huanlogo_new >/dev/null 2>&1
    $ADB -s "$TV" push "$TMP/adInfo_new" /data/local/tmp/adInfo_new >/dev/null 2>&1
    $ADB -s "$TV" push "$TMP/video_empty" /data/local/tmp/video_empty >/dev/null 2>&1
    rm -rf "$TMP"
    echo "▸ 1/4 关配置开关 + 清广告信息 + 视频归零"
    tv "$BH chattr -i /data/logo/config/huanlogo /data/logo/media4/adInfo /data/logo/media4/video.ts 2>/dev/null; \
        $BH cp /data/local/tmp/huanlogo_new /data/logo/config/huanlogo; $BH chown 1000:1000 /data/logo/config/huanlogo; $BH chmod 600 /data/logo/config/huanlogo; \
        $BH cp /data/local/tmp/adInfo_new /data/logo/media4/adInfo; $BH chown 1000:1000 /data/logo/media4/adInfo; $BH chmod 600 /data/logo/media4/adInfo; \
        $BH cp /data/local/tmp/video_empty /data/logo/media4/video.ts; $BH chown 1000:1000 /data/logo/media4/video.ts; $BH chmod 777 /data/logo/media4/video.ts"
    echo "▸ 2/4 锁死（immutable，防止重新下载写回）"
    tv "$BH chattr +i /data/logo/config/huanlogo /data/logo/media4/adInfo /data/logo/media4/video.ts"
    echo "▸ 3/4 属性双保险"
    tv "setprop persist.sys.logo.time 0; setprop third.bootanimation.close 1"
    echo "▸ 4/4 结果"
    tv "cat /data/logo/config/huanlogo; echo; cat /data/logo/media4/adInfo; echo; $BH ls -la /data/logo/media4/video.ts; $BH lsattr /data/logo/config/huanlogo /data/logo/media4/adInfo /data/logo/media4/video.ts; echo logo.time=\$(getprop persist.sys.logo.time)" | sed 's/^/   /'
    echo "✅ 完成（isOpen=false / adInfo=[] / video.ts=0字节 / 全部 immutable / logo.time=0）"
    echo "   回滚：./65d2p.sh shell \"busybox chattr -i /data/logo/config/huanlogo /data/logo/media4/adInfo /data/logo/media4/video.ts\" 再从 $NAS 拷回"
    ;;

  fix-home)
    # ⭐ 修「切到 HDMI/DTV 后按遥控器主页键没反应」
    #    真因：Settings.Secure.user_setup_complete=0 且 Settings.Global.device_provisioned=0，
    #    ActivityManagerService.startHomeActivityLocked() 认为"用户设置未完成"，直接拒绝启动桌面，
    #    只在 logcat 里留一条：Not starting activity because user setup is in progress。
    #    （所以 am start -a MAIN -c HOME 能回，按键 HOME 回不去 —— 两条路径的检查不一样）
    ensure_conn
    echo "▸ 当前值"
    tv 'echo -n "  secure user_setup_complete = "; settings get secure user_setup_complete; \
        echo -n "  global device_provisioned   = "; settings get global device_provisioned'
    echo "▸ 修正为 1"
    tv 'settings put secure user_setup_complete 1; settings put global device_provisioned 1'
    echo "▸ 修正后"
    tv 'echo -n "  secure user_setup_complete = "; settings get secure user_setup_complete; \
        echo -n "  global device_provisioned   = "; settings get global device_provisioned'
    echo "✅ 完成。现在切到 HDMI/DTV 后按遥控器「主页」键即可回到当贝桌面"
    echo "   验证：./65d2p.sh shell \"input keyevent 3\" 然后看前台是否变成 com.dangbei.tvlauncher"
    ;;

  home-apk)
    # 信号源一键切换 APK（见 hdmi1/）：HDMI1 / HDMI2 / DTV / AV / 回系统桌面 / 信号源菜单
    ensure_conn
    APK="$(dirname "$0")/hdmi1/build/信号源切换-HDMI1.apk"
    [ -f "$APK" ] || { echo "❌ 找不到 APK：$APK（先跑 hdmi1/build.sh）"; exit 1; }
    $ADB -s "$TV" install -r "$APK" 2>&1 | tail -2
    tv "pm grant org.sharmy.chsource android.permission.WRITE_SETTINGS 2>&1; true" >/dev/null 2>&1
    echo "✅ 已安装：桌面会多出 6 个图标（机顶盒 HDMI1 / HDMI2 / DTV / AV / 回到系统桌面 / 信号源菜单）"
    echo "   注：这只是快捷入口；主页键要根治请跑 ./65d2p.sh fix-home"
    ;;

  *)
    sed -n '2,20p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'
    ;;
esac
