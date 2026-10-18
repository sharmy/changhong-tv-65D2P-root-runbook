# 长虹 65D2P 电视 root / 去广告 / 封 OTA 实战手册

一台长虹 65D2P（机芯 `ZLH74GiR`、系统 `V1.00039`、Android 5.1.1）从打通 adb 到彻底消灭开机广告的完整记录，
含可一键执行的维护脚本。所有操作均可回滚。

> 完成于 2026-10-18，**开机广告已实测消除**（重启验证通过）。
> 文中 IP / MAC 等均为本机真实值，保留以便后续直接用；若要公开分享请自行替换。

---

## 文件说明

| 文件 | 用途 |
|---|---|
| [`65D2P-root-runbook.md`](65D2P-root-runbook.md) | **主文档**。设备档案、ADB 打通、去广告、封 OTA、换桌面、回滚全流程 |
| [`65d2p.sh`](65d2p.sh) | 一键维护脚本（root 身份执行，幂等，可重复跑） |
| [`hosts_block`](hosts_block) | 广告 / 升级域名黑名单（62 个，含长虹官方清单 + 爱奇艺 Cupid） |
| `65D2P-CHLogoService-处置与恢复方案.md` | CHLogoService 单项的处置与恢复步骤 |

## 快速开始

```bash
./65d2p.sh            # 查看所有子命令
./65d2p.sh status     # 看状态（root / ADB / 禁用数 / 当前桌面）
./65d2p.sh lock-all   # 一键：封 OTA + 禁广告推送包
```

### 子命令一览

| 命令 | 作用 |
|---|---|
| `kill-bootlogo-ad` | ⭐ **去开机广告（真凶）**，见下文 |
| `kill-iqiyi-bootad` | 爱奇艺 TV 版 Cupid 开机屏广告 |
| `hosts-lock` / `hosts-unlock` | 启用 / 还原广告域名拦截 |
| `lock-db-bootad` | 锁当贝桌面"开机直达"广告开关 |
| `replace-db <apk>` | 换当贝桌面（清残留 + 装纯净版 + 锁开关） |
| `lock-all` / `restore` | 封 OTA+禁广告 / 全部回滚 |
| `ota-lock` / `adblock` | 单独封 OTA / 单独禁广告 |
| `switch-home` / `restore-home` | 切当贝桌面 / 恢复长虹桌面 |
| `fix-adb` | 重启后 adb 失联急救（顺带恢复 hosts 拦截） |
| `install <apk>` / `pkgs` / `shell <cmd>` | 装应用 / 列包 / 执行任意命令 |

---

## ⭐ 开机广告的真正答案

**不是任何 App 的广告，是长虹系统自己的开机广告位**：

```
/system/bin/bootanimation（长虹定制 native 进程）
   ↓ 读 /data/logo/config/huanlogo
     {"isOpen":"true","adServer":"http://ads.huan.tv/a.gif","materialPath":"/data/logo/media4"}
   ↓ 读 /data/logo/media4/adInfo
     {"position":"...KJGG-2B-TS-1080P","material":"http://adsboot-cdn.cedock.com/...ts","d":15}
   ↓ 播放 /data/logo/media4/video.ts（15 秒）
```

**为什么常见的办法都没用**：

| 办法 | 无效原因 |
|---|---|
| 禁用 CHLogoService / 华数 recognizecore | 播放者是 native 的 `bootanimation`，不是 App |
| 换当贝桌面纯净版 | 这是系统级，与桌面无关 |
| hosts 封广告域名 | 素材已在本地，**断网照样播** |
| 开机后跑脚本恢复 | 广告在 adb 连得上之前就播完了 |

**有效处置**（一键 `./65d2p.sh kill-bootlogo-ad`），全部落在可写分区并 `chattr +i` 锁死，重启仍有效：

1. `huanlogo` → `"isOpen":"false"`
2. `adInfo` → `[]`
3. `video.ts` → 0 字节
4. `setprop persist.sys.logo.time 0`
5. `setprop third.bootanimation.close 1`

原文件自动备份到电视 `/data/local/tmp/logo_backup/`，可随时回滚。

### 排查方法论（踩过 6 次误判才总结出来）

1. **先问清行为，再看日志**：断网能否播？在桌面之前还是之后？——这两个观察比 logcat 更快定位方向。
2. **开机广告先看这两个**：
   ```bash
   adb shell getprop | grep -iE "bootanim|logo"
   strings /system/bin/bootanimation | grep -iE "third|logo"
   ```
   长虹定制版会暴露 `ro.third.bootanimation.path_*`、`persist.sys.logo.time` 等属性。
3. **App 层禁用无效 → 立刻转向 native 进程 + 可写数据分区**（`/data/logo`、`/data/data/...`）。
4. **logcat 主缓冲只有约 4000 行**，开机早期请求常被冲掉，别只信它；配合 events 缓冲和数据目录缓存一起看。

---

## 前提：如何拿到 root adb

1. 原厂固件自带 `/system/xbin/su`（无需刷机，KingRoot 只是确认了一遍）
2. 装 SimpleSSHD（端口 2222），设 `onboot=true` 开机自启 + 固化公钥免密
3. 重启后 adbd 常以 shell 身份起来，跑 `./65d2p.sh fix-adb` 用三行配方拉起 root adbd：
   ```bash
   setprop persist.service.adb.enable 0
   setprop service.adb.root 1
   setprop persist.service.adb.enable 1
   ```
4. 电视 shell 极简（无 `grep`/`sed`/`head`），一律走 `/system/bin/busybox ...`

---

## 已知限制

- `/system` 是只读 ext4，`mount -o remount,rw` 报 `Operation not permitted`
  → hosts 改用 **bind mount** 绕过（重启失效，已并入 `fix-adb`）
- 电视 shell 里 `ping` / `nslookup` 均不可用（DNS 不走 shell resolver），
  **别用它们判断 hosts 是否生效**，要看 app 层 logcat 的 `ECONNREFUSED`
- SimpleSSHD 无"启动命令"配置，无法靠它自动化执行开机脚本

---

## 免责

仅供自家设备学习研究，操作前请确认型号与机芯一致（**ZLH74GiR ≠ ZLH74Gi2G**，固件不可混刷）。
所有改动均可回滚，但仍请自行承担风险。
