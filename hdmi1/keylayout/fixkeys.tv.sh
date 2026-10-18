#!/system/bin/sh
# ============================================================
# 电视端执行：重做 keylayout bind mount（遥控器主页键修复）
# 由本地 65d2p-autofix-keys.sh 推送并以 root 身份调用：
#     sh /data/local/tmp/ch_fixkeys.sh
# 输出最后一行为 MOUNTS=<n>，本地脚本据此判断是否成功（应为 2）。
# ============================================================

SRC_DIR=/data/chkeys
TMP_DIR=/data/local/tmp
SYS_DIR=/system/usr/keylayout
A=Vendor_0001_Product_0001.kl
B=Vendor_046d_Product_0002.kl

# 1) 保证源文件在 /data/chkeys（/data 被清时从 /data/local/tmp 恢复）
mkdir -p $SRC_DIR
for f in $A $B; do
  if [ ! -s "$SRC_DIR/$f" ] && [ -s "$TMP_DIR/$f" ]; then
    cp "$TMP_DIR/$f" "$SRC_DIR/$f"
  fi
done
chmod 644 $SRC_DIR/$A 2>/dev/null
chmod 644 $SRC_DIR/$B 2>/dev/null

if [ ! -s "$SRC_DIR/$A" ] || [ ! -s "$SRC_DIR/$B" ]; then
  echo "ERR: 缺少 keylayout 源文件，先跑 ./65d2p.sh fix-keys"
  echo "MOUNTS=0"
  exit 1
fi

# 2) 先 umount 再 mount（避免 adb push 覆盖造成挂载点变成 (deleted)）
umount $SYS_DIR/$A 2>/dev/null
umount $SYS_DIR/$B 2>/dev/null
mount -o bind $SRC_DIR/$A $SYS_DIR/$A 2>&1
mount -o bind $SRC_DIR/$B $SYS_DIR/$B 2>&1

# 3) 自检
grep -c keylayout /proc/mounts
echo "MOUNTS=$(grep -c keylayout /proc/mounts)"
