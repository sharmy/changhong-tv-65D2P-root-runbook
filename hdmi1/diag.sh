#!/bin/bash
# 诊断：切到 HDMI 后为什么回不到安卓系统
# 用法： ./hdmi1/diag.sh          先跑只读诊断
#        ./hdmi1/diag.sh watch    清日志后等你按遥控器「主页」键，抓 10 秒日志
cd "$(dirname "$0")/.."

ADB="$(command -v adb)"; [ -x "$ADB" ] || ADB=/tmp/pt/platform-tools/adb
TV=192.168.1.2:5555
tv() { $ADB -s $TV exec-out sh -c "$1" 2>&1; }
BB=/system/bin/busybox

$ADB connect $TV >/dev/null 2>&1
tv "id" | head -1

echo
echo "===== 1) 当前前台 Activity ====="
tv "dumpsys activity activities 2>/dev/null | $BB grep -E 'mFocusedActivity|topResumedActivity|mResumedActivity' | $BB head -4"
tv "dumpsys window windows 2>/dev/null | $BB grep -E 'mCurrentFocus|mFocusedApp' | $BB head -3"

echo
echo "===== 2) 当前信号源 / 支持的源 ====="
tv "am start -n org.sharmy.chsource/.Hdmi1 --es source __LIST__ >/dev/null 2>&1"
sleep 3
tv "logcat -d -v brief 2>&1 | $BB grep 'I/ChSourceSwitch' | $BB tail -2"

echo
echo "===== 3) 视频层相关进程 ====="
tv "ps 2>/dev/null | $BB grep -E 'Tvmain|tvap|chdtv|HDMIRX|atv' | $BB head -10"

echo
echo "===== 4) 试发 HOME intent，看谁接管 ====="
tv "logcat -c >/dev/null 2>&1"
tv "am start -a android.intent.action.MAIN -c android.intent.category.HOME 2>&1 | $BB head -3"
sleep 3
echo "--- 发完 HOME 后前台："
tv "dumpsys window windows 2>/dev/null | $BB grep -E 'mCurrentFocus' | $BB head -2"
echo "--- 日志："
tv "logcat -d -v brief 2>&1 | $BB grep -iE 'ActivityManager.*START|home|launcher' | $BB tail -8"

if [ "$1" = "watch" ]; then
  echo
  echo "===== 5) 按键抓日志：请现在按遥控器「主页」键（10 秒）====="
  tv "logcat -c >/dev/null 2>&1"
  sleep 10
  tv "logcat -d -v brief 2>&1 | $BB grep -iE 'key|home|KeyCode|dispatch|tvap|launcher' | $BB tail -25"
fi
