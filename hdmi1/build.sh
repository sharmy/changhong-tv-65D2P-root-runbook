#!/bin/bash
# 长虹 65D2P 信号源一键切换 APK —— 手工构建（不依赖 Gradle / Android Studio）
# 需要：JDK 17 + aapt2 + d8 + zipalign + apksigner
set -e
cd "$(dirname "$0")"

JDK="/tmp/android/jdk-17.0.20.1+1/Contents/Home"
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
    "$OUT/res.zip"

echo "▸ 2/5 编译 Java（javac → .class）"
"$JAVAC" -source 8 -target 8 -bootclasspath "$PLAT/android.jar" \
    -d "$OUT/classes" src/org/sharmy/chsource/SwitchActivity.java

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
