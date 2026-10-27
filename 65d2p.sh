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
#   fix-home    修「切到 HDMI/DTV 后按主页键没反应」之①：user_setup_complete=0 系统拒绝启动桌面
#   fix-keys    修「遥控器主页键压根没反应」之②：keylayout 把主页键映射成无效 keycode
#               （bind mount 重启即失效；正常由 APK 自动重挂，见 heal）
#   home-apk    装信号源一键切换 APK（HDMI1/HDMI2/DTV/AV/回系统桌面/信号源菜单）
#   heal        手动触发一次 keylayout 自愈（正常不需要：APK 开机 1~2 分钟内自动做）
#   bootlogo <图> [秒]  自定义开机画面（换成自己照片，默认显示 8 秒）
#   bootlogo-restore    还原长虹原厂开机图
#   bootlogo-test       不重启，就地预览一次当前开机画面
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

# ---- 经 SimpleSSHD(2222) 在电视上执行命令（admin 用户，免密）----
# 传大文件用 ssh 更稳：adbd 只有一个连接位，电视端自愈（Healer）出问题时也会来抢，
# 容易把 Mac 的会话挤掉（传 3MB 图片曾半路 EOF）。ssh 没这个限制。
# ⚠ SimpleSSHD 不是常驻的，电视重启后要在电视上手动打开一次，否则 2222 拒连。
# ⚠ ssh 里跑 am 必须加 --user 0，否则报
#     SecurityException: startActivity asks to run as user -2 but is calling from user 0
#     （adb shell 是 shell 用户，没这问题；admin=u0_a26 有）
# admin = u0_a26，能写 /sdcard 和 /data/logo/media4(777)、能 setprop，
# 但读不了 /data/local/tmp（shell:shell 771）。
tvssh() {
  ssh -p "$SSH_PORT" -i "$SSH_KEY" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=8 "admin@${TV%%:*}" "$1" 2>/dev/null
}
# 同名文件用 scp 推过去
tvcpsend() {
  scp -P "$SSH_PORT" -i "$SSH_KEY" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=10 "$1" "admin@${TV%%:*}:$2" >/dev/null 2>&1
}

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
    echo "✅ 完成。若遥控器主页键仍然没反应，说明还差 fix-keys（keylayout 那层）："
    echo "   ./65d2p.sh fix-keys"
    echo "   验证：./65d2p.sh shell \"input keyevent 3\" 然后看前台是否变成 com.dangbei.tvlauncher"
    ;;

  fix-keys)
    # ⭐ 修「遥控器主页键压根没反应」（比 fix-home 更底层的一层）
    #    真因：主页键的扫描码 91 在 keylayout 里被映射成长虹私有 keycode CHANGHONGIR_HOME，
    #    而本机 libinputflinger 的 keycode 标签表里没有这个名字 → 解析结果 keyCode=0
    #    （KEYCODE_UNKNOWN），WindowManager 直接判为 Unhandled key 丢弃，logcat：
    #      D WindowManager: Unhandled key: win=..., keyCode=0, scanCode=91
    #    dumpsys input 查到的映射文件：
    #      Hi keyboard (event0)               -> /system/usr/keylayout/Vendor_0001_Product_0001.kl
    #      Changhong Smart TV Keypad (event3) -> /system/usr/keylayout/Vendor_046d_Product_0002.kl
    #      注意：名字会骗人，"Changhong Smart TV Keypad" 用的其实是 Vendor_046d_Product_0002.kl
    #      （只映射了 5 个方向键），遥控器真正的按键走的是 "Hi keyboard"。
    #    /system 是 ext4 ro 且 remount 被拒（Operation not permitted），改不了 →
    #    用 bind mount 覆盖 /data/chkeys 下的修复版；bind mount 重启即失效，所以开机后要重跑。
    ensure_conn
    KL_DIR="$(dirname "$0")/hdmi1/keylayout"
    [ -d "$KL_DIR" ] || { echo "❌ 找不到 $KL_DIR"; exit 1; }
    tv 'mkdir -p /data/chkeys'
    for f in Vendor_0001_Product_0001.kl Vendor_046d_Product_0002.kl; do
      tv "umount /system/usr/keylayout/$f 2>/dev/null; true" >/dev/null
      $ADB -s "$TV" push "$KL_DIR/$f" "/data/chkeys/$f" >/dev/null
      tv "chmod 644 /data/chkeys/$f"
      tv "mount -o bind /data/chkeys/$f /system/usr/keylayout/$f 2>&1; true"
    done
    echo "▸ 覆盖后的主页键映射："
    tv 'busybox grep "key 91" /system/usr/keylayout/Vendor_0001_Product_0001.kl /system/usr/keylayout/Vendor_046d_Product_0002.kl'
    echo "▸ 重启框架让 inputflinger 重新加载 keymap（约 30 秒，画面会闪一下）"
    # ⚠ 光发 ctl.restart 不够：bootcomplete 之前发会被 init 直接忽略（2026-10-27 踩过，
    #   表现是"挂载数是 2，但按主页键毫无反应"）。发完必须校验 system_server 真换了，
    #   没换就 kill -9 硬来（zygote 发现 system_server 死了会自杀，init 重新拉起整个框架）。
    sspid() { tv 'ps | grep system_server | awk "NR==1{print \$2}"' | tr -dc '0-9'; }
    SS0="$(sspid)"; echo "   重启前 system_server pid=$SS0"
    tv 'setprop ctl.restart zygote' >/dev/null
    SS1=""
    for i in $(seq 1 18); do            # 最多等 90 秒
      sleep 5
      P="$(sspid)"
      if [ -n "$P" ] && [ "$P" != "$SS0" ]; then SS1="$P"; break; fi
    done
    if [ -z "$SS1" ] && [ -n "$SS0" ]; then
      echo "   ctl.restart 没生效，直接 kill -9 $SS0"
      tv "kill -9 $SS0" >/dev/null
      sleep 40
      SS1="$(sspid)"
    fi
    echo "   重启后 system_server pid=${SS1:-未变（失败）}"
    echo "✅ 完成。等电视画面回来后，切到 HDMI 再按遥控器「主页」键即可回到当贝桌面"
    echo "   自检：./65d2p.sh shell 'sendevent /dev/input/event0 1 91 1; sendevent /dev/input/event0 1 91 0; sendevent /dev/input/event0 0 0 0'"
    echo "        再看 logcat 是否出现 keyCode=3 + START cat=[HOME] 当贝"
    echo "   注意：电视重启后 bind mount 失效，需重跑本命令"
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
    echo "   装完请打开一次本 app（会注册开机自愈任务），并在电视管家 → 权限管理里"
    echo "   给「信号源」打开 自动启动 / 后台运行，然后【重启电视一次】才生效"
    echo "   （/chperm/preapp/killbackground 名单是 system_server 开机时读一次的）"
    ;;

  heal)
    # 手动触发一次开机自愈：重挂 keylayout + 软重启框架。
    # 正常不需要跑 —— APK 里的 JobScheduler 任务会在开机 1~2 分钟内自动做掉。
    ensure_conn
    echo "▸ 触发自愈（电视端完成，约 30~60 秒，中途会软重启一次框架）..."
    tv "am start -n org.sharmy.chsource/.Home --es source __HEAL__ >/dev/null 2>&1; true"
    sleep 25
    echo "▸ 等自愈完成 + zygote 重启（约 40 秒，期间 adb 会断）"
    sleep 40
    ensure_conn
    N="$(tv 'grep -c keylayout /proc/mounts' | tr -d '\r')"
    echo "keylayout 挂载数 = $N （应为 2）"
    [ "$N" -ge 2 ] 2>/dev/null && echo "✅ 主页键已恢复" \
      || echo "❌ 没挂上，看 logcat：$ADB -s $TV exec-out sh -c 'logcat -d -s ChSourceHeal'"
    ;;

  bootlogo)
    # 自定义开机画面：把任意图片做成开机静态图，替换掉原来那张（原本是长虹 logo）。
    # 用法： ./65d2p.sh bootlogo ~/Pictures/我家.jpg [显示秒数，默认 8]
    #
    # 原理：属性 ro.third.str.logo.path = /chperm/logo/media/STRbootlogo.png
    #   → 软链到 /data/logo/media4/STRbootlogo.png（可写分区）
    #   → /system/bin/bootanimation 开机进 STR 模式直接画这张图（已 logcat 验证）
    #   → 显示时长由 persist.sys.logo.time 控制（persist，重启保留）
    # 规格：1920x1080、8bit、RGB（不要 alpha，否则可能画不出来）
    IMG="$2"; SEC="$3"
    [ -n "$IMG" ] || { echo "用法：./65d2p.sh bootlogo <图片> [秒数]"; exit 1; }
    [ -f "$IMG" ] || { echo "❌ 找不到图片：$IMG"; exit 1; }
    [ -n "$SEC" ] || SEC=8

    # 找一个装了 Pillow 的 python
    PY=""
    for c in /Users/bob/.workbuddy/binaries/python/envs/default/bin/python3 \
             /Users/bob/.workbuddy/binaries/python/envs/default/bin/python python3; do
      if command -v "$c" >/dev/null 2>&1 && "$c" -c "import PIL" >/dev/null 2>&1; then PY="$c"; break; fi
    done
    [ -n "$PY" ] || { echo "❌ 找不到带 Pillow 的 python（需要它来转 1920x1080 PNG）"; exit 1; }

    OUT="/tmp/bootlogo_1920x1080.png"
    echo "▸ 转换图片 → 1920x1080 RGB PNG（等比裁剪铺满）"
    "$PY" - "$IMG" "$OUT" <<'PYEOF'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
W, H = 1920, 1080
im = Image.open(src).convert("RGB")
print("   原图 %dx%d" % (im.width, im.height))
sr, tr = im.width / im.height, W / H
if sr > tr:                       # 偏宽，裁左右
    nw = int(im.height * tr); x = (im.width - nw) // 2
    im = im.crop((x, 0, x + nw, im.height))
else:                             # 偏高，裁上下
    nh = int(im.width / tr); y = (im.height - nh) // 2
    im = im.crop((0, y, im.width, y + nh))
im.resize((W, H), Image.LANCZOS).save(dst, "PNG", optimize=True)
print("   已生成 %s（%.1f MB）" % (dst, __import__("os").path.getsize(dst) / 1048576.0))
PYEOF

    SIZE=$(wc -c < "$OUT" | tr -dc '0-9')
    echo "▸ 传输到电视（${SIZE} 字节）"
    OK=0
    GOT=0

    # 原厂图只备份一次，避免把「上一张自定义图」当成原厂备份
    tvssh "mkdir -p /sdcard/logo_backup; \
           [ -f /sdcard/logo_backup/STRbootlogo.orig.png ] \
             || cp /chperm/logo/media/STRbootlogo.png /sdcard/logo_backup/STRbootlogo.orig.png" >/dev/null 2>&1

    # 通道 1（首选）：SimpleSSHD —— 不受 adbd 单连接限制
    if tvssh "echo ok" | grep -q ok; then
      # 目标文件是 root:root 644，admin 只能「删了重建」，不能直接覆写
      tvssh "rm -f /data/logo/media4/STRbootlogo.png"
      if tvcpsend "$OUT" /data/logo/media4/STRbootlogo.png; then
        GOT=$(tvssh "busybox wc -c /data/logo/media4/STRbootlogo.png" | awk '{print $1}' | tr -dc '0-9')
        if [ "$GOT" = "$SIZE" ]; then
          OK=1
          echo "   通道：SimpleSSHD，字节数校验通过"
        fi
      fi
    fi

    # 通道 2（兜底）：adb。adbd 只有一个连接位，电视端 Healer 每 60~120 秒来抢一次，
    # 传 3MB 容易半路断 —— 所以先传到临时文件、校验字节数，通过了才覆盖开机图，
    # 否则会留下一个截断的 PNG，开机就是坏图/黑屏。
    if [ $OK -eq 0 ]; then
      echo "   SimpleSSHD 通道未成功（ssh 不通或 scp 失败），改用 adb 兜底"
      ensure_conn
      tv "rm -f /data/local/tmp/logo_new.png"
      $ADB -s "$TV" push "$OUT" /data/local/tmp/logo_new.png >/dev/null 2>&1
      GOT=$(tv "wc -c < /data/local/tmp/logo_new.png 2>/dev/null" | tr -dc '0-9')
      if [ "$GOT" = "$SIZE" ]; then
        tv "cp /data/local/tmp/logo_new.png /data/logo/media4/STRbootlogo.png && \
            chmod 644 /data/logo/media4/STRbootlogo.png"
        OK=1
        echo "   通道：adb，字节数校验通过"
      fi
    fi

    [ $OK -eq 1 ] || { echo "❌ 两条通道都失败（期望 $SIZE，实际 ${GOT:-0}），开机图未改动"; exit 1; }

    # 显示时长：admin 也能 setprop（已实测）
    if ! tvssh "setprop persist.sys.logo.time $SEC" 2>/dev/null; then
      ensure_conn; tv "setprop persist.sys.logo.time $SEC"
    fi
    echo "✅ 开机画面已替换，显示 ${SEC} 秒（重启生效）"
    echo "   原厂图备份：电视 /sdcard/logo_backup/STRbootlogo.orig.png"
    echo "   还原：./65d2p.sh bootlogo-restore"
    ;;

  bootlogo-restore)
    R=""
    # 注：电视的 sh 很精简，没有 wc/stat/head/tail/strings；要数大小得用 busybox wc
    if tvssh "[ -f /sdcard/logo_backup/STRbootlogo.orig.png ] && echo yes" | grep -q yes; then
      tvssh "rm -f /data/logo/media4/STRbootlogo.png; \
             cp /sdcard/logo_backup/STRbootlogo.orig.png /data/logo/media4/STRbootlogo.png" \
             >/dev/null 2>&1
      R=$(tvssh "busybox wc -c /data/logo/media4/STRbootlogo.png" | awk '{print $1}' | tr -dc '0-9')
    fi
    if [ -z "$R" ]; then
      ensure_conn
      tv "cp /data/local/tmp/logo_backup/STRbootlogo.orig.png /data/logo/media4/STRbootlogo.png \
          && chmod 644 /data/logo/media4/STRbootlogo.png" >/dev/null 2>&1
      R=$(tv "wc -c < /data/logo/media4/STRbootlogo.png" | tr -dc '0-9')
    fi
    [ -n "$R" ] && echo "✅ 已还原长虹原厂开机图（$R 字节，重启生效）" \
                || echo "❌ 还原失败：找不到备份（/sdcard/logo_backup/ 或 /data/local/tmp/logo_backup/）"
    ;;

  bootlogo-test)
    # 不重启、就地拉起一次 bootanimation，看当前开机图长什么样（几秒后自动停）
    ensure_conn
    tv "logcat -c; setprop service.bootanim.exit 0; setprop ctl.start bootanim" >/dev/null 2>&1
    echo "▸ 已拉起开机画面（电视屏幕会被覆盖几秒）"
    sleep 5
    $ADB connect "$TV" >/dev/null 2>&1; sleep 2
    tv "logcat -d 2>&1 | grep -iE 'strbootlogo|goto STR'" 2>&1
    tv "setprop service.bootanim.exit 1; setprop ctl.stop bootanim" >/dev/null 2>&1
    echo "✅ 已停止开机画面，电视恢复正常"
    ;;

  *)
    sed -n '2,20p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'
    ;;
esac
