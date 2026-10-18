# 长虹 65D2P — CHLogoService（开机广告）处置与恢复方案

> 生成：2026-10-18。取证与处置均基于实机（ZLH74GiR / V1.00039 / Android 5.1.1）。
> 当前状态：**已禁用**。本文档含完整的禁用/恢复/验证步骤，均可直接复制执行。

## 1. 组件档案

| 项 | 值 |
|---|---|
| 包名 | `com.changhong.huan.logo.service` |
| APK 位置 | `/system/app/CHLogoService/CHLogoService.apk`（462KB，2017-08-17 出厂自带） |
| 版本 | 3.2.0 |
| 运行身份 | **uid 1000（system）**，gids 含 inet(3003)/sdcard_rw(1015)/log(1007) 等 |
| 包标志 | SYSTEM + DEBUGGABLE |

### 1.1 关键权限（granted，节选高危项）

```
android.permission.REAL_GET_TASKS          # 读取任意前台任务
android.permission.INSTALL_PACKAGES        # 静默安装
android.permission.SHUTDOWN                # 关机
android.permission.MASTER_CLEAR            # 恢复出厂！
android.permission.SYSTEM_ALERT_WINDOW     # 悬浮窗（广告全屏展示的根基）
android.permission.RESTART_PACKAGES        # 杀后台
android.permission.CLEAR_APP_USER_DATA     # 清应用数据
android.permission.RECEIVE_BOOT_COMPLETED  # 开机自启
android.permission.WRITE_SETTINGS
android.permission.ACCESS_FINE_LOCATION    # 定位（广告定向）
android.permission.ACCESS_CACHE_FILESYSTEM
android.permission.DOWNLOAD_WITHOUT_NOTIFICATION  # 静默下载广告素材
```

→ 这不是"壁纸工具"，是拿了一整套系统特权的广告投放服务。

## 2. 组件清单与启动顺序

### 2.1 LaunchReceiver（唯一广播接收器，广告入口）

监听 3 个 action（按开机时序）：

| 顺序 | Action | 来源 | 含义 |
|---|---|---|---|
| ① 最早 | `com.changhong.dmt.system.boot_part1` | 长虹 dmt 开机管理器 | 冷启动早期（早于系统就绪）即触发 |
| ② | `android.intent.action.BOOT_COMPLETED` | 系统 | 开机完成兜底（①失败还有②） |
| ③ | `STR_CHiQ_POWER_ON` | 长虹 CHiQ 待机唤醒链 | **待机唤醒也会触发**，不只冷开机 |

### 2.2 两个工厂 Activity（未在广告链路上，但随包禁用）

| 组件 | Action | 用途 |
|---|---|---|
| `.usertool.UsbFileCopyActivity` | `com.changhong.dmt.system.logo.Usb_Copy` | 工厂/售后用 U 盘刷开机 Logo |
| `.usertool.UserConfigActivity` | `com.changhong.dmt.system.logo.USER_CONFIG` | 工厂用户配置工具 |

### 2.3 广告链路（日志取证，2026-10-18 冷启动抓包）

```
LaunchReceiver 启动服务
  → HTTP GET ads.huan.tv          # 环广告SDK 拉广告单（明文HTTP，可被光猫过滤）
      广告位 CH-HSV551-changhong-KJGG-2B-TS-1080P   （15秒视频，CanExit=1 可跳过）
      广告位 CH-HSV551-changhong-KJGG-STR-PNG-1080P （开机静态图，AppOpenTime=15 强制15秒）
  → GET adsboot-cdn.cedock.com/ad-link/…​.ts|.png   # 下载素材（15s视频约6.7MB）
  → 全屏播放（SYSTEM_ALERT_WINDOW）
  → 曝光打点 monitor-ads.huan.tv（HTTPS）+ ads.huan.tv/*.gif
```

## 3. 禁用步骤（已执行 ✅ 2026-10-18 14:20）

```bash
# 前置：root adb（见 runbook §1.5；失联先跑 ./65d2p.sh fix-adb）
ADB="/tmp/pt/platform-tools/adb -s 192.168.1.2:5555"

# 1) 禁用整个包（同时覆盖 LaunchReceiver 和两个工厂 Activity）
$ADB exec-out sh -c 'pm disable com.changhong.huan.logo.service'
#   预期输出: Package com.changhong.huan.logo.service new state: disabled

# 2) 杀掉当前已运行的进程（禁用不杀存量）
$ADB exec-out sh -c 'am force-stop com.changhong.huan.logo.service'

# 3) 验证
$ADB exec-out sh -c 'pm list packages -d | /system/bin/busybox grep huan'
#   预期: package:com.changhong.huan.logo.service
$ADB exec-out sh -c 'ps | /system/bin/busybox grep logo.service'
#   预期: 无输出（进程已死）
```

禁用效果（pm disable 是持久状态，重启不会复活）：
- 三个开机广播全部无人接收 → 广告服务不会启动
- 开机直接进桌面，无 15 秒广告、无开机静态图
- **最坏影响 = 开机无长虹 Logo 动画**（黑屏几秒后进当贝桌面），无其他功能损失

## 4. 恢复步骤（如需回滚）

```bash
ADB="/tmp/pt/platform-tools/adb -s 192.168.1.2:5555"

# 完整恢复（重启后开机广告会回来）
$ADB exec-out sh -c 'pm enable com.changhong.huan.logo.service'
#   预期: Package com.changhong.huan.logo.service new state: enabled

# 立即拉起（不等重启）
$ADB exec-out sh -c 'am startservice -n com.changhong.huan.logo.service/.service.LogoService' 2>/dev/null \
  || $ADB exec-out sh -c 'am broadcast -a com.changhong.dmt.system.boot_part1'
# 注：服务精确组件名可用 dumpsys package 查询；广播方式一定有效（模拟开机触发）

# 验证恢复
$ADB exec-out sh -c 'pm list packages -d | /system/bin/busybox grep huan'   # 应无输出
```

恢复的合理场景：
- 出售/退还电视前还原出厂行为
- 怀疑某些长虹"开机自检/首次开机向导"异常（目前无证据相关）
- 售后上门检修前（避免售后以"私改系统"为由推诿）

## 5. 只禁广播、保留包（备选方案，当前未采用）

若只想让广告不弹、但保留工厂工具可用：

```bash
# 精确禁用 LaunchReceiver（广播收不到 = 广告不会启动）
$ADB exec-out sh -c 'pm disable com.changhong.huan.logo.service/.receiver.LaunchReceiver'
# 恢复：
$ADB exec-out sh -c 'pm enable com.changhong.huan.logo.service/.receiver.LaunchReceiver'
```

> 当前采用了整包禁用（更彻底）；此方案作为颗粒度更细的备选记录。

## 6. 重启验证流程（固定动作）

每次想确认广告确实没回来，按此执行：

```bash
# ① 禁用状态还在吗（重启后 pm 状态应保持 disabled）
./65d2p.sh shell "pm list packages -d | /system/bin/busybox grep huan"

# ② 进程没起？（广告服务只在开机时活跃，平时查 ps 应无）
./65d2p.sh shell "ps | /system/bin/busybox grep -i logo"

# ③ 广告网络请求没了？（抓当前日志，不应再出现 huan/adsboot）
./65d2p.sh shell "logcat -d -t 2000" | grep -ciE "huan|adsboot"
#   预期: 0  （>0 说明有残留请求，检查 ①②）

# ④ 肉眼确认：重启后应直接进当贝桌面，全程无 15 秒视频/静态广告图
```

## 7. 风险与边界

| 项 | 评估 |
|---|---|
| 禁用后系统稳定性 | 低风险：包是独立 service 应用，无其他系统组件依赖它（Receiver 只进不出） |
| OTA/升级影响 | 无：升级组件已单独禁用（见 runbook §4），与 CHLogoService 互不依赖 |
| 开机时间 | 略缩短（不再等 15 秒广告） |
| `pm disable` 持久性 | **持久**（写入 /data/system，重启保留） |
| 被系统复活的可能性 | 仅当恢复出厂 或 手动 pm enable；长虹 OTA 已被三层封死（runbook §4） |
| 工厂 Activity 一并失效 | 接受（U盘刷Logo/用户配置为售后专用，日常无用途） |

## 8. 关联文件

- 日常操作：`65d2p.sh`（CHLogoService 已列入 AD_PKGS，`lock-all`/`restore` 自动覆盖）
- 总手册：`65D2P-root-runbook.md`（§1.5 adb 急救 / §3 广告包清单）
- 取证日志：`/tmp/tvboot.log`（2026-10-18 14:09 冷启动，含完整广告请求链）
