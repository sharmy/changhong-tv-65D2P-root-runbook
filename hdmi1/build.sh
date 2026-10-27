#!/bin/bash
# 长虹 65D2P 信号源一键切换 APK —— 手工构建（不依赖 Gradle / Android Studio）
# 需要：JDK 17 + aapt2 + d8 + zipalign + apksigner
set -e
cd "$(dirname "$0")"

# ⚠ /tmp 会被系统清掉，JDK / build-tools 都得重装过。所以这里一律自动探测，
#   找不到就把下载命令直接打出来（别让人再去翻历史记录）。
if [ -n "$JDK_HOME" ] && [ -x "$JDK_HOME/bin/javac" ]; then
  JDK="$JDK_HOME"
else
  JDK="$(ls -d /tmp/android/jdk-17*/Contents/Home /tmp/android/jdk-17*.jdk/Contents/Home \
         2>/dev/null | head -1)"
fi
if [ ! -x "$JDK/bin/javac" ]; then
  echo "❌ 找不到 JDK 17（/tmp 被清过？）。国内可直接下腾讯 Kona："
  echo "   curl -sL -o /tmp/android/kona17.tar.gz https://cnb.cool/tencent/TencentKona/TencentKona-17/-/releases/download/TencentKona-17.0.14/TencentKona-17.0.14.b1_jdk_macosx-aarch64_notarized.tar.gz"
  echo "   tar xzf /tmp/android/kona17.tar.gz -C /tmp/android"
  exit 1
fi
if [ ! -x /tmp/android/bt_t/android-13/aapt2 ]; then
  echo "❌ 找不到 build-tools。下载："
  echo "   curl -sL -o /tmp/android/bt.zip https://dl.google.com/android/repository/build-tools_r33.0.1-macosx.zip && unzip -q -o /tmp/android/bt.zip -d /tmp/android/bt_t"
  exit 1
fi
if [ ! -f /tmp/android/plat_t/android-11/android.jar ]; then
  echo "❌ 找不到 android.jar(API 30)。下载："
  echo "   curl -sL -o /tmp/android/plat.zip https://dl.google.com/android/repository/platform-30_r03.zip && unzip -q -o /tmp/android/plat.zip -d /tmp/android/plat_t"
  exit 1
fi
BT="/tmp/android/bt_t/android-13"
PLAT="/tmp/android/plat_t/android-11"
AAPT2="$BT/aapt2"; D8="$BT/d8"; ZIPALIGN="$BT/zipalign"; APKSIGNER="$BT/apksigner"
JAVAC="$JDK/bin/javac"; KEYTOOL="$JDK/bin/keytool"

export JAVA_HOME="$JDK"; export PATH="$JDK/bin:$PATH"

OUT="build"; APK_UNALIGNED="$OUT/chsource-unsigned.apk"; APK="$OUT/信号源切换-HDMI1.apk"
KS="keystore/chsource.jks"

rm -rf "$OUT"; mkdir -p "$OUT/classes" "$OUT/res" keystore

echo "▸ 1/5 编译资源（aapt2 compile + link）"
"$AAPT2" compile --dir res -o "$OUT/res.zip"
"$AAPT2" link -o "$APK_UNALIGNED" \
    -I "$PLAT/android.jar" \
    --manifest AndroidManifest.xml \
    --min-sdk-version 22 --target-sdk-version 22 \
    --java "$OUT/gen" \
    -A assets \
    "$OUT/res.zip"

echo "▸ 2/5 编译 Java（javac → .class）"
find src -name '*.java' > "$OUT/sources.txt"
"$JAVAC" -source 8 -target 8 -bootclasspath "$PLAT/android.jar" \
    -d "$OUT/classes" @"$OUT/sources.txt"

echo "▸ 3/5 打包 dex（d8）"
(cd "$OUT/classes" && "$JDK/bin/jar" cf ../classes.jar .)
"$D8" --min-api 22 --lib "$PLAT/android.jar" --output "$OUT/" "$OUT/classes.jar"
ls -l "$OUT/classes.dex"

echo "▸ 4/5 合并 dex 进 APK + zipalign"
cd "$OUT"
"$JDK/bin/jar" uf "../$APK_UNALIGNED" classes.dex || \
    /usr/bin/zip -q "../$APK_UNALIGNED" classes.dex
cd ..
"$ZIPALIGN" -f 4 "$APK_UNALIGNED" "$OUT/aligned.apk"

echo "▸ 5/5 签名"
if [ ! -f "$KS" ]; then
  "$KEYTOOL" -genkeypair -v -keystore "$KS" -alias chsource \
      -keyalg RSA -keysize 2048 -validity 10950 \
      -storepass changhong -keypass changhong \
      -dname "CN=ChangHong 65D2P, OU=TV, O=sharmy, L=CQ, C=CN" >/dev/null
fi
"$APKSIGNER" sign --ks "$KS" --ks-key-alias chsource \
    --ks-pass pass:changhong --key-pass pass:changhong \
    --out "$APK" "$OUT/aligned.apk"

echo
echo "✅ 构建完成：$(pwd)/$APK"
ls -l "$APK"
"$AAPT2" dump badging "$APK" | head -8
