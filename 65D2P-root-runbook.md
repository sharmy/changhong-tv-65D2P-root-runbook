# 长虹 65D2P 电视 root / 去广告 / 封 OTA 操作手册

> 首次完成：2026-10-18。下次直接照第 1 节执行，无需重新摸索。

## 0. 设备档案

| 项 | 值 |
|---|---|
| 整机型号 | 长虹 65D2P |
| **机芯** | **ZLH74GiR**（≠ ZLH74Gi2G，固件不可混刷） |
| 系统版本 | V1.00039-ZLH74GiR-BuildTime.2017.08.17 |
| Android | 5.1.1 / API 22 / arm64-v8a / 海思 hisi551_SEC |
| 电视 IP | `192.168.1.2`（MAC `0e:e4:00:34:81:d0`，DLNA 名 `65D2P_81D0`） |
| Mac 本机 | `192.168.1.36` |
| 光猫/路由 | `192.168.1.1`（ONT V175，管理页 `/index.asp`） |
| root 来源 | **原厂固件自带** `/system/xbin/su`（2017-08-17，setuid root，组 shell）；KingRoot 只是确认了一遍 |
| ADB | `5555`，`ro.adb.secure=0` 免认证，已 `persist.adb.tcp.port=5555` 持久化 |

## 1. 下次直接这样做（三行）

```bash
cd /Users/bob/WorkBuddy/2026-10-17-21-36-44
./65d2p.sh status      # 看状态
./65d2p.sh lock-all    # 一键：封 OTA + 禁广告（幂等，可重复跑）
```

## 1.5 ADB 失联急救（2026-10-18 重启实战验证，优先看这里）

**重启电视后 adb 的真实行为（实测）**：5555 端口会起来（adbd 被 init 拉起），但
`persist.service.adb.enable` 开机被系统重置、`service.adb.root=0`，adbd 以 **shell** 身份
运行 → 长虹密码门生效，exec-out 狂弹 `Password:`。**不能指望自愈**，但一条命令可救：

```bash
cd /Users/bob/WorkBuddy/2026-10-17-21-36-44
./65d2p.sh fix-adb
```

内部原理（三行配方，SSH 通道全部免密）：

```bash
ssh -p 2222 -i tvkey admin@192.168.1.2   # SimpleSSHD 通道（公钥已固化，免密）
  setprop persist.service.adb.enable 0   # ① 触发 Changhong init 补丁 stop adbd
  setprop service.adb.root 1             # ② root 标志（app 权限即可设！）
  setprop persist.service.adb.enable 1   # ③ 触发 start adbd → 以 root 运行 → 免密
```

关键事实：
- Changhong init 补丁：`persist.service.adb.enable=1 → start adbd`、`=0 → stop adbd`，
  且**这两个属性 + `service.adb.root` app 权限（u0_a26）就能设置**——等于厂门钥匙插在锁上
- adbd 启动瞬间读 `service.adb.root` 决定身份：root → 密码门完全旁路；shell → 全通道要密码
- **开机自启不可靠（两次重启实测）**：`persist.service.adb.enable` 会被系统重置；长虹 ROM
  不给第三方应用投递 BOOT_COMPLETED（SimpleSSHD 的 onboot=true 无效）。重启后 5555 与
  2222 都可能不在线，**必须手动开一次 SimpleSSHD**（遥控器打开 → Start），再跑 `fix-adb`
- sshd 可用广播远程控制（root adb 下）：`am broadcast -a org.galexander.sshd.START` /
  `.STOP`（实测有效）
- 禁用包/桌面等状态重启不丢（pm disable 是持久的）
- 可选优化：当贝市场（com.dangbeimarket）若有「管理 → 开机自启」功能，把 SimpleSSHD
  加进去（当贝桌面是 HOME 应用、开机必活，由它拉起比系统广播可靠）

陷阱备忘：
- 原厂 `/system/xbin/su` 只许 `shell` 组执行，app uid（SimpleSSHD 的 shell）执行会 Permission denied
- 改 hosts / 重挂 /system 都不行（root 也无 CAP_SYS_ADMIN），维护一律走 `65d2p.sh` 的 exec-out 通道
- SimpleSSHD 的密码是**每连接一次性生成**（屏幕日志 `generating single-use password:` 之后那行），
  单连接最多 3 次试错；用公钥则完全无需密码
- KingRoot 已卸载（其临时 root 不持久，且整机链路已不依赖它）

脚本自动定位 adb（`$ADB_BIN` → PATH → `/tmp/pt/platform-tools/adb`）。
若 adb 丢失：

```bash
cd /tmp && curl -sL -o pt.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip && unzip -q pt.zip -d /tmp/pt
```

## 2. 关键技巧：绕过长虹的 ADB shell 密码（必读）

裸 `adb shell` 会弹 `Password:` —— 长虹把默认 shell 换成了定制 login，常见密码
（123456 / 0000 / changhong / hisilicon / admin / root…）**全部错误**，pty 交互实测均 Access denied。

**绕过方式（三种都直接给 uid=0 root）：**

```bash
adb exec-out id                       # ✅
adb shell /system/bin/sh -c "id"      # ✅
adb shell -- id                       # ✅
```

→ 脚本里统一封装成 `adb exec-out sh -c "<命令>"`。

## 3. A. 禁用广告 / 推送 / 预装游戏 / 开机广告（12 个）

| 包名 | 是什么 |
|---|---|
| `com.changhong.chchoujiangfortv` | 抽奖运营 |
| `com.changhong.chhongbaofortv` | 红包运营 |
| `com.changhong.spanner` | 广告条 / 悬浮推送 |
| `com.changhong.chrecommendersystem` | 内容推荐 |
| `com.changhong.pointstore` | 积分商城 |
| `com.changhong.chnoticesystem` | 通知推送 |
| `com.changhong.inspection` | 巡检上报（隐私） |
| `com.changhong.remoteassistance` | 远程协助（后门） |
| `com.egame.tv` | 预装游戏大厅 |
| `com.tencent.tvgamehall` | 腾讯游戏大厅 |
| `com.changhong.huan.logo.service` | **开机广告**（CHLogoService，环广告SDK：ads.huan.tv 分发 → adsboot-cdn.cedock.com 拉素材，15s视频+开机图；2026-10-18 取证后加入。禁用最坏影响=开机无Logo动画；回滚 `pm enable`） |
| `tv.huan.recognizecoreV551` | **开机营销弹窗（京东双11类电商全屏图真凶）**：华数"识别核心"，system uid 1000 出厂预装，监听 BOOT_COMPLETED + `com.changhong.dmt.system.boot_part3`；组件含 FloadWindowReciver（**悬浮窗**展示，不产生 Activity 启动日志）、LancherStatuReceiver（监听默认桌面是否长虹→换当贝后触发）、ChanghongRecommenderReceiver、数据目录 HuanTVlogoModel、代码含 RedPacketForecastCategory 红包营销类（2026-10-18 取证后加入；可能影响语音/华数识别功能，可 `pm enable` 回滚） |

### 3.1 当贝桌面"开机直达"页（冷开机的全屏影视推荐图，2026-10-18 处置）

不是包禁用，是改配置 + 锁文件：

```bash
# 开关在 all_message JSON：switch_on=1(开)/0(关)，switch_time=5(秒)
# 注意：直接改 0 会被桌面启动时的服务器配置刷新覆盖回 1，必须 chattr +i 锁定
adb exec-out sh -c '/system/bin/busybox chattr -i /data/data/com.dangbei.tvlauncher/shared_prefs/share_data.xml'   # 先解锁
# （改 all_message 里 "switch_on":1 → 0，sed 或 pull/push）
adb exec-out sh -c '/system/bin/busybox chattr +i /data/data/com.dangbei.tvlauncher/shared_prefs/share_data.xml'   # 再上锁
# 回滚：chattr -i 后把 0 改回 1（或让桌面联网刷新自动恢复）
```
> 该值是当贝代码默认值（服务器接口不下发此字段），网络层封不掉；锁文件后桌面运行正常。
> **一键命令**：`./65d2p.sh lock-db-bootad`（自动取 uid → 改 0 → chown → chmod → chattr +i）

### 3.1.1 换成当贝桌面 4.1.7 纯净版（2026-10-18 15:15 完成）

用户提供 `当贝桌面4.1.7纯净版_20250330(testkey签名).apk`（8.1MB），替换官方版。

**为什么必须卸载重装**：官方版与 testkey 纯净版签名不同，`install -r` 会
`INSTALL_FAILED_UPDATE_INCOMPATIBLE`；卸载后直接装又会 `INSTALL_FAILED_UID_CHANGED`
（残留 `/data/data/com.dangbei.tvlauncher` 的旧 uid 未清）。

**正确顺序（脚本 `./65d2p.sh replace-db <apk>` 已封装）**：
1. `pm enable com.changhong.system.launcher.v2` ← **先恢复长虹桌面当安全网**（否则卸载后无桌面可用，可能黑屏）
2. `pm uninstall com.dangbei.tvlauncher`
3. **解锁 + 清残留**：`busybox chattr -R -i /data/data/com.dangbei.tvlauncher` 再 `rm -rf`
   （⚠️ 之前为锁广告加过 `chattr +i share_data.xml`，不解锁 rm 会报 `Operation not permitted`，残留清不掉就装不上）
4. `adb install -r <纯净版.apk>`
5. `./65d2p.sh lock-db-bootad` ← 纯净版**默认 switch_on=1**，必须再锁一次
6. 电视上首次启动：同意协议 → 选**「精美壁纸」**（选"推荐"会显示 APP 内容推荐位）
7. `pm disable com.changhong.system.launcher.v2` 恢复当贝为唯一 HOME

**纯净版 vs 官方版差异（dumpsys 实测）**：
- 官方 versionCode=117；纯净版 versionCode=20250330，同为 versionName 4.1.7
- 纯净版**移除了 `com.talkingdata.sdk.TDAntiCheatingService`**（TalkingData 统计/广告 SDK）
- 纯净版保留 `share_data.xml` 开机直达模块（所以仍需第 5 步锁定）

### 3.6 ⭐⭐ 开机广告**终极真凶**：长虹 bootanimation + /data/logo（2026-10-18 15:55 定案，15:56 重启验证通过 ✅）

> ✅ **2026-10-18 15:56 用户重启确认：开机广告消失。** 这是唯一有效的方案。
>
> 用户三条观察直接破案：**① 断网也能播 ② 广告后才进当贝（当贝显示"桌面准备中"）③ 是电视自己的、缓存在本地**。

**机制（完整链路）**：
```
/system/bin/bootanimation（长虹定制 native 进程）
   ↓ 读 /data/logo/config/huanlogo
     {"isOpen":"true","adServer":"http://ads.huan.tv/a.gif","materialPath":"/data/logo/media4"}
   ↓ 读 /data/logo/media4/adInfo
     [{"position":"CH-HSV551-changhong-KJGG-2B-TS-1080P","name":"video.ts","isputad":true,
       "monitor_url":"http://ads.huan.tv/x.gif?...&adt=boot&d=15",
       "material":"http://adsboot-cdn.cedock.com/ad-link/2026-09-24/....ts"}]
   ↓ 播放 /data/logo/media4/video.ts（6.4MB，出厂版才 4.4MB，说明后来下载替换过）
   ↓ 播 15 秒（persist.sys.logo.time=15）
```
`KJGG` = 开机广告。`/chperm/logo/media/video.ts` 是符号链接 → `/data/logo/media4/video.ts`。
`/chperm` 挂载 `ext4 rw`；`/data/logo` 全可写。

**为什么之前所有方案都无效**：
- 禁用 CHLogoService / recognizecore → 没用，**播放是 bootanimation native 进程干的**，不是 app
- 换当贝纯净版 / 删爱奇艺缓存 → 没用，这是系统级
- hosts 封域名 → 没用，**素材已在本地，断网照样播**
- 开机后跑脚本恢复 → 没用，广告在 bootanimation 阶段（比 adb 早得多）

**bootanimation 里的关键属性**（`strings /system/bin/bootanimation`）：
`ro.third.bootanimation.path_one/path_two`、`third.finish.bootvideo.count`、`persist.sys.logo.time`、
`third.bootanimation.close`、`ro.third.str.logo.path`、`sys.str.bootanim.start`

**处置（一键：`./65d2p.sh kill-bootlogo-ad`）——全部落在可写分区 + immutable，重启仍有效**：
1. `huanlogo` → `"isOpen":"false"` + `chattr +i`
2. `adInfo` → `[]` + `chattr +i`
3. `video.ts` → 0 字节 + `chattr +i`
4. `setprop persist.sys.logo.time 0`（持久）
5. `setprop third.bootanimation.close 1`

备份在 `/data/local/tmp/logo_backup/`（huanlogo.bak 保留 `isOpen:true` 原版、adInfo.bak 3195B）。
回滚：先 `busybox chattr -i` 三个文件，再从备份拷回。

> ⚠ 脚本备份逻辑已修：`.bak` 已存在时跳过（`[ -f $B ] || cp`），避免二次运行用已改内容覆盖原始备份。

### 3.5 ⭐ 爱奇艺TV版 Cupid 开机屏广告 —— **开机广告的真正真凶**（2026-10-18 15:35 定案）

**为什么之前一直没找到**：素材是**本地缓存**的，开机时根本不联网回放缓存，
所以表现为"开机即播、进系统前已经放完"，**hosts / 抓开机网络请求都拦不住也抓不到**。

**决定性证据**：`/data/data/com.gitvdemo.video/files/cupidBootScreenResponse`（62KB）
```json
"urlConfig": {"mixer":"https://t7z.cupid.ptqy.gitv.tv/mixer",
              "creative":"https://t7z.cupid.ptqy.gitv.tv/creative",
              "cupidTracking":".../track2", "realtimeMixer":"http://kjp.cupid.ptqy.gitv.tv/mixer"}
"bkcrs": [{"renderType":"video","duration":"15",
           "url":"http://data.video.ptqy.gitv.tv/videos/other/.../xxx.mp4"}]   ← 12 条 15 秒开机视频
"interstitialConfig": {"interval":7200,"maxImpression":100}
```
`bkcrs` = boot screen creatives = 开机屏素材；`Cupid` 是爱奇艺广告 SDK。

**为什么"装当贝前没有广告"**：长虹桌面在前台盖住了它；换当贝桌面后裸露（与腾讯视频 §3.2 同一机制）。

**处置（一键： `./65d2p.sh kill-iqiyi-bootad`）——前两层重启仍有效，不依赖开机执行**：
1. `pm disable com.gitvdemo.video/com.gala.video.app.boot.autoboot.QYBootCompleteReceiver` ← **持久**
2. 删 `cupidBootScreenResponse` / `marketing_dynamic` / `DynamicCache` / MD5 命名的缓存素材
   **再以 `chattr +i` 建 0 字节占位** → 没素材可播、也写不回去 ← **持久**
3. hosts 封 `t7z.cupid.ptqy.gitv.tv`、`kjp.cupid.ptqy.gitv.tv`、`data.video.ptqy.gitv.tv`、
   `msg.ptqy.gitv.tv`、`v2.reachmax.cn`、`*.miaozhen.com` 等 12 个（重启失效，靠 1+2 兜底）

> ⚠ 素材 CDN（`data.video.ptqy.gitv.tv`、`pic*.ptqy.gitv.tv`）同时也是爱奇艺正片/封面源，
> 封了可能影响看剧；不看爱奇艺就不用管，看的话从 `hosts_block` 删掉那几行。
> 实测 app 不崩溃，仅广告请求 `ECONNREFUSED`。

### 3.2 腾讯视频开机开屏广告（2026-10-18 处置）

> ⚠️ **更正（2026-10-18 15:05）**：本节最初认定腾讯视频是"京东双11电商全屏图"真凶，
> 但第5次重启取证（boot5.log）证实：三个接收器已禁、进程未被拉起，**广告仍在**。
> 电商全屏图真凶实为 §3.3 的 `tv.huan.recognizecoreV551`（悬浮窗）。
> 本节处置仍然保留——腾讯视频开屏广告是独立的一层，禁了没坏处。

冷开机全屏电商广告（右上角"07 广告"倒计时）另一嫌疑是出厂预装的 **com.ktcp.video**（腾讯视频TV版）：
长虹开机广播唤醒其 `CHRestoreBroadcastReceiver` → 进程启动 → `get_splash_screen` 拉开屏广告。
以前长虹桌面在前台盖住它；换当贝桌面后裸露。

```bash
# 精确禁用三个开机接收器（App本体保留，桌面手动打开照常可用）
pm disable com.ktcp.video/.receiver.CHRestoreBroadcastReceiver
pm disable com.ktcp.video/.receiver.BootstrapProjectionReceiver
pm disable com.ktcp.video/com.tencent.device.receiver.IOTStartReceiver
am force-stop com.ktcp.video
# 回滚：对应 pm enable
```
> 手动打开腾讯视频时仍会有 App 内开屏广告（那是应用自身行为）。

```bash
./65d2p.sh adblock
# 手动等价：adb exec-out sh -c "pm disable <包名>"
```

**用 `pm disable` 不用 `pm uninstall`** —— 可逆，出问题能一键恢复。

### 3.4 广告 hosts 拦截（/system 只读的绕过办法，2026-10-18 实战）

**结论：`/system` 改不了，但 hosts 拦截可以做，用 bind mount 绕过。**

```bash
# /system 是只读 ext4，remount 直接失败：
mount -o remount,rw /system   →  mount: Operation not permitted
# 原 hosts 只有一行：/system/etc/hosts → "127.0.0.1  localhost"
```

**绕过办法**：把 `/data` 上可写的 hosts **bind mount** 覆盖到 `/system/etc/hosts`（root 可行）：

```bash
adb push hosts_block /data/local/tmp/hosts
adb exec-out sh -c "chmod 644 /data/local/tmp/hosts; mount -o bind /data/local/tmp/hosts /system/etc/hosts"
# 一键： ./65d2p.sh hosts-lock      撤销： ./65d2p.sh hosts-unlock
```

**生效铁证**（app 层真实请求，非推测）：
```
E/b: java.net.ConnectException: Failed to connect to otysdktj.tvfuwu.com/127.0.0.1:80
     ECONNREFUSED (Connection refused)
```

**验证注意**：电视 shell 里 `ping` / `busybox nslookup` **都不可用**（连 `www.baidu.com` 也
`bad address`），**不要用它判断 hosts 是否生效**——DNS 不走 shell resolver。
要用 app 层验证：重启当贝后抓 logcat 看是否 `ECONNREFUSED ... 127.0.0.1`。

**局限**：bind mount **重启即失效**。已并入 `./65d2p.sh fix-adb`（开机必跑），
跑一次同时恢复 root adb + hosts。SimpleSSHD 只有 `onboot` 配置项，**没有"启动命令"**，
无法靠它自动化。

**已知可用**：`/system/bin/iptables` 存在（385KB），可作为按 IP/网段封禁的兜底手段。

**当前黑名单：`hosts_block`（脚本同目录，49 个域名）**
来源 = 用户提供的《长虹电视禁止广告升级网址统计》+ 本机实测补充的当贝系。

> ⚠ **格式陷阱**：那份统计文件是 `127.0.0.1 a.com;b.com;` 的**分号分隔格式（非标准 hosts）**，
> 原样使用会全部失效（分号被当成域名的一部分）。必须按分号拆成每个域名一行。

| 分组 | 数量 | 说明 |
|---|---|---|
| 广告/统计/桌面配置 | 26 | `ads.huan.tv`、`chc.ads.huan.tv`、`launcher.smart-tv.cn`、`jfapi.chiq-cloud.com` 等 |
| 系统升级 | 5 | `*.changhong.upgrade2.huan.tv`、`sys-update.ch.hifuntv.com`（封了正好，OTA 已另禁） |
| 当贝推荐/统计 | 7 | `zmapi.dangbei.net`、`otysdktj.tvfuwu.com`、`adsboot-cdn.cedock.com` 等 |
| ⚠ 语音识别 | 5 | `scs.openspeech.cn`、`itv2-up.openspeech.cn`、`dev.voicecloud.cn` 等——**封了遥控器语音失效** |
| ⚠ NTP 时间同步 | 4 | `0.cn.pool.ntp.org`、`s3a.time.edu.cn` 等——实测封后电视时间仍准确 |
| ⚠ 账号认证 | 2 | `authenticate.chiq-cloud.com`、`uapi.chiq-cloud.com` |

实测拦截命中（app 层 logcat）：`itv2-up.openspeech.cn`、`otysdktj.tvfuwu.com`、`zmapi.dangbei.net`。
不需要某项就在 `hosts_block` 里删掉那几行，再跑 `./65d2p.sh hosts-lock`。

### 3.3 华数 recognizecore 开机营销弹窗（京东双11类电商全屏图真凶，2026-10-18 处置）

**排查史（防止再走弯路）**：电商全屏图广告连续 5 次重启都在，先后误判为
①当贝开机直达（锁 switch_on=0 无效）②CHLogoService（禁后日志零活动但广告仍在）
③腾讯视频开屏（禁后 boot5.log 证实未拉起但广告仍在）。
最终在第5次开机日志里发现 `tv.huan.recognizecoreV551`（uid 1000）由
BootCompletedReceiver 拉起 → 解包 APK 证实嫌疑。

**证据链**：
- `/system/app/tv.huan.recognizecore/tv.huan.recognizecore.apk`，出厂预装（2017-08-17），system uid 1000
- manifest：监听 `BOOT_COMPLETED` + `com.changhong.dmt.system.boot_part3`（长虹开机链第3段）
- 组件：`FloadWindowReciver`（**悬浮窗**展示端——悬浮窗不走 Activity，logcat 无 START u0 记录，这是前三次排查盲区的根因）、`LancherStatuReceiver`（监听默认桌面，换当贝后触发）、`ChanghongRecommenderReceiver`、`MainActivity`、`MainService`
- 数据目录有 `HuanTVlogoModel`（开机Logo模型）；运行日志有 `RedPacketForecastCategory`（红包营销）、连 `www.epg.huan.tv`

**处置**：
```bash
pm disable tv.huan.recognizecoreV551
am force-stop tv.huan.recognizecoreV551
# 回滚：pm enable tv.huan.recognizecoreV551
```
已并入 `./65d2p.sh adblock` / `lock-all` 的 AD_PKGS 清单（第12个）。

**风险**：包名为"识别核心"，理论上可能承担语音/内容识别，若语音助手异常先 `pm enable` 回滚本包验证。
**验证方法**：重启电视，若开机不再出现京东/电商全屏图 → 定案；若仍有 → 回滚本包，改查
`com.changhong.chusercenter`（长虹用户中心，开机请求 jfapi.chiq-cloud.com 积分API，第2938号进程）。

## 3.7 信号源一键切换 APK（HDMI1 机顶盒 / HDMI2 / DTV / AV / 信号源菜单）★2026-10-18 实机验证通过

需求：桌面上放一个图标，点一下直接切到 HDMI1（机顶盒），不用再按遥控器「信号源」再选。

### 结论：能切，而且用的就是系统内部同一条调用链

系统把 `/system/framework/com.changhong.tvos.jar` 写进了 `BOOTCLASSPATH`
（`/init.environ.rc` 可见），**任意第三方 app 都能直接反射调用长虹私有 TVOS SDK**：

```java
TVManager.getInstance(ctx)                       // com.changhong.tvos.common
        .getATVPlayer()                          // com.changhong.tvos.atv.IATVPlayer
        .startInputSource(EnumInputSource.E_INPUT_SOURCE_HDMI, 15);
```

这跟系统「信号源」菜单（`com.changhong.SourceMenu` → `MenuSource.changeSource`）
**是同一句代码**（反汇编 `SourceMenu.apk` 的 dex 可证）。

### 关键事实（逆向所得，别再重复摸索）

| 项 | 值 |
|---|---|
| SDK jar | `/system/framework/com.changhong.tvos.jar`（BOOTCLASSPATH，无需打包进 APK） |
| 服务 | `ServiceManager.getService("CHTVService")` → `com.changhong.tvos.service.ITVService`（跑在 system_server，pid 1985） |
| 切换 API | `ITVPlayer.startInputSource(EnumInputSource, int)` **返回 boolean**，第二参（15）在 `PlayerImpl` 里被硬编码成 0，随便传 |
| 备用 API | `ISourceManager.selectInputSource(EnumInputSource)`；切完再 `getCurInputSource(E_MAIN_INPUT_SOURCE)` 读回校验 |
| `EnumInputSource` 序号 | ATV=0, DTV=1, CVBS=2…, **HDMI=19（HDMI1）**, HDMI2=20, HDMI3=21, HDMI4=22 … 共 35 个 |
| 本机实际支持 | **ATV, DTV, CVBS, HDMI1, HDMI2**（`getInputSourceList()` 实测，**没有 HDMI3**） |
| 坑 1 | `TVManager.getInstance()` **要带 Context 参数**（`getInstance(Context)`），无参版不存在 |
| 坑 2 | 切源会写 `Settings.System` → 缺 `WRITE_SETTINGS` 会被抛 `SecurityException: Permission denial: writing to settings`；manifest 声明即可，必要时 `pm grant` |
| 坑 3 | 切完系统会自己拉起 `com.changhong.tvap.atv.activity.AtvMainActivity`（与遥控器操作一致，属正常） |

### 交付物

`hdmi1/` 目录（源码 + 手工构建脚本，**不需要 Android Studio / Gradle**）：

| 图标 | 作用 |
|---|---|
| 机顶盒 HDMI1 | 切到 `E_INPUT_SOURCE_HDMI` |
| HDMI2 | 切到 `E_INPUT_SOURCE_HDMI2` |
| 数字电视 DTV | 切到 `E_INPUT_SOURCE_DTV` |
| AV 音视频 | 切到 `E_INPUT_SOURCE_CVBS` |
| **回到系统桌面** | **从 HDMI/DTV 切回安卓系统（等价遥控器「主页」键）** |
| 信号源菜单 | 直接弹系统原生信号源浮层 |

实现要点：一个 `SwitchActivity` + 5 个 `activity-alias`，每个 alias 用
`<meta-data android:name="source" android:value="E_INPUT_SOURCE_HDMI">` 声明目标源，
Activity 里读 alias 的 metaData 决定切哪个 —— 一份代码出多个桌面图标。

```bash
# 构建（需 JDK 17 + aapt2/d8/zipalign/apksigner，build.sh 里自动找 /tmp/android 下的工具链）
cd hdmi1 && ./build.sh

# 安装
adb install -r hdmi1/build/信号源切换-HDMI1.apk
# 若报 SecurityException: writing to settings
adb exec-out sh -c "pm grant org.sharmy.chsource android.permission.WRITE_SETTINGS"

# adb 直接切（不点图标也行）
adb exec-out sh -c "am start -n org.sharmy.chsource/.Hdmi1"
# 查询本机支持的信号源
adb exec-out sh -c "am start -n org.sharmy.chsource/.Hdmi1 --es source __LIST__"
adb exec-out sh -c 'logcat -d | /system/bin/busybox grep I/ChSourceSwitch'
```

### 实机验证结果（2026-10-18）

```
Hdmi2 -> 已切换到 HDMI2
Dtv   -> 已切换到 DTV
Hdmi1 -> 已切换到 HDMI1
Av    -> 已切换到 CVBS
Menu  -> 已打开信号源菜单
Hdmi1 -> 已切换到 HDMI1
```

### 3.7.1 切到 HDMI 后主页键没反应 ★★★ 真因：user_setup_complete=0

**现象**：切到 HDMI/DTV 后按遥控器「主页」键毫无反应，只能看到 TV 画面；
但用 `adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME`
却能正常回到当贝桌面。**两条路结果不一样**，这是破案的关键。

**真因**（2026-10-18 实测定位，logcat 铁证）：

```
I/WindowManager: Not starting activity because user setup is in progress:
Intent { act=android.intent.action.MAIN cat=[android.intent.category.HOME] flg=0x10200000 }
```

系统**认为「用户设置未完成」**，`ActivityManagerService.startHomeActivityLocked()`
直接拒绝启动桌面 —— 而且**静默失败**，不打异常、不弹提示，所以看起来就像"按键坏了"。

对应两个设置项（本机出厂/被改后就是 0）：

| 设置项 | 原值 | 正确值 |
|---|---|---|
| `Settings.Secure.user_setup_complete` | `0` | `1` |
| `Settings.Global.device_provisioned` | `0` | `1` |

**修复（一行命令，持久生效）**：

```bash
./65d2p.sh fix-home
# 等价于：
adb exec-out sh -c "settings put secure user_setup_complete 1; settings put global device_provisioned 1"
```

**修复后实测（4 轮回归全部通过）**：

| 进源 | 按主页键后前台 | 截图大小 |
|---|---|---|
| HDMI1 | com.dangbei.tvlauncher | 18KB → 757KB |
| HDMI2 | com.dangbei.tvlauncher | → 583KB |
| DTV | com.dangbei.tvlauncher | → 583KB |
| HDMI1 | com.dangbei.tvlauncher | → 583KB |

日志同时变成正常：`START u0 {act=MAIN cat=[HOME] cmp=com.dangbei.tvlauncher/...} from uid 1000`。

**为什么 `am start` 能绕过**：`am start` 走普通 `startActivity`，不做
`startHomeActivityLocked` 的「用户设置是否完成」检查；而按键走
`launchHomeFromHotKey → startHomeActivityLocked`，会检查。这就是两者不一致的原因。

**附带结论**：
- **信号源菜单里没有「Android / 智能系统」这一项**（`getInputSourceList()` 实测只有
  ATV/DTV/CVBS/HDMI1/HDMI2），**别去信号源菜单里找回去的入口**——找不到。
- 回到系统是**前台 Activity 切换**，不是信号源切换；TV 画面窗口是
  `com.changhong.tvap.atv.activity/.AtvMainActivity`。
- APK 里的「回到系统桌面」图标（发 HOME intent）可作为主页键的备用入口。

**排查过程中被排除的错误方向（别再走一遍）**：
- ❌ 「HDMI 视频层置顶盖住了安卓 UI」——`dumpsys SurfaceFlinger` 里当贝桌面图层
  `isOpaque=1`、全屏、z=21005，并不存在遮挡；截图能直接拍到桌面。
- ❌ 「杀掉 TV 播放器进程 `com.changhong.tvap.atv.activity`」——杀了只会变成
  "无信号请检查输入"黑屏，桌面依旧不出来（因为问题在 HOME 启动被拒，不是资源占用）。
- ❌ `ITVPlayer.stop()` / `muteVideo()`——TVServiceHandler 每个方法第一行都是
  `checkClientResource(调用方pid)`，第三方 app 不持有资源，直接 return（`stop()` 恒为 false）。
- ❌ `startInputSource(E_INPUT_SOURCE_NONE / OTHER)`——均返回 false，本机不支持。

**调试技巧（省很多来回）**：`screencap` 能直接反映真实屏幕，截图大小还能当快速判据
（当贝桌面约 580~760KB，TV 黑屏"无信号"约 18~28KB），全程不用人盯着电视看：

```bash
adb exec-out screencap -p > /tmp/s.png && stat -f%z /tmp/s.png
```

### 3.7.2 主页键还是没反应 ★★★ 第二层真因：keylayout 把主页键映射成无效 keycode

修完 3.7.1 后用户反馈**遥控器主页键仍然没反应**。这时 `input keyevent 3` 依旧有效，
说明"系统肯启动桌面"，问题在**按键根本没被解析成 HOME**。

**铁证（logcat，按一下遥控器主页键就看到）**：

```
D WindowManager: interceptKeyTi keyCode=0 down=true ... deviceName=Hi keyboard
D WindowManager: Unhandled key: win=Window{...AtvMainActivity}, action=0,
                 keyCode=0, scanCode=91, metaState=0
```

`keyCode=0` 就是 `KEYCODE_UNKNOWN` —— WindowManager 把它当"没人要的键"直接丢了。

**根因链**：

1. 遥控器主页键的 Linux 扫描码是 **91**。
2. `/system/usr/keylayout/Vendor_0001_Product_0001.kl`（长虹红外键表）里写的是
   `key 91     CHANGHONGIR_HOME`。
3. 本机 `libinputflinger.so` 的 keycode 标签表里**没有** `CHANGHONGIR_HOME` 这个名字
   （长虹私有 keycode，本版本框架已不带），解析失败 → 落成 0。
   （对照：同文件里 `key 76 STAIR_SOURCE` 能正常解析成 `keyCode=2001`，说明标签表只有部分私有键。
   另注意 `CHANGHONGIR_HOME` 与我们的 APK 里用的 `keyCode 2001` 不是一回事。）
4. 于是主页键从"按下"到"丢弃"一步都没走到 `launchHomeFromHotKey()`。

**关键的设备名陷阱（我在这里绕了两轮）**：`dumpsys input` 里设备名和键表文件名对不上，
**名字会骗人**，必须逐块解析：

| 设备（`getevent -p` / `dumpsys input`） | 节点 | 实际加载的 keylayout |
|---|---|---|
| `Hi keyboard` | `/dev/input/event0` | `Vendor_0001_Product_0001.kl` ← **遥控器真正的按键走这条** |
| `Changhong Smart TV Keypad` | `/dev/input/event3` | `Vendor_046d_Product_0002.kl` ← 只有 5 个方向键 |

先按"Changhong Smart TV Keypad"这个名字去改 `Vendor_0001_...` 是改错了文件，
改完毫无变化。正确查法：

```bash
# 把 dumpsys input 拉回来，按 "N: 设备名" 分块，逐块找 KeyLayoutFile
adb exec-out dumpsys input > /tmp/in.txt
```

**修复（两条路径都补 `key 91 HOME`）**：

```bash
./65d2p.sh fix-keys
```

脚本做的事：`hdmi1/keylayout/` 里两份修复版推到 `/data/chkeys/`，`mount -o bind`
覆盖 `/system/usr/keylayout/` 下的同名文件，再 `setprop ctl.restart zygote`
让 inputflinger 重新加载键表（画面会黑 30 秒左右）。

- `/system` 是 `ext4 ro`，`mount -o remount,rw /system` 返回 `Operation not permitted`，
  只能 bind mount；**bind mount 重启即失效**，电视重启后要重跑 `fix-keys`。
- `/data/system/devices/keylayout/` 这个 AOSP 覆盖目录**本机不生效**（实测放进去后
  `dumpsys input` 仍解析 `/system/usr/keylayout/...`），别浪费时间。

**验证技巧（很重要）**：`input keyevent 3` 是**注入路径，跳过 keylayout**，
所以"注入有效"完全不能证明"按键有效"。要复现真实按键必须写 `sendevent` 打原始扫描码：

```bash
# 模拟按一次遥控器主页键（扫描码 91，event0 = Hi keyboard）
adb shell 'sendevent /dev/input/event0 1 91 1; \
           sendevent /dev/input/event0 1 91 0; \
           sendevent /dev/input/event0 0 0 0'
```

**修复后实测（2026-10-18）**：

| 步骤 | 前台 | 截图 |
|---|---|---|
| 切 HDMI1（进源） | `com.changhong.tvap.atv.activity/.AtvMainActivity` | 18KB（无信号黑屏） |
| `sendevent 91`（模拟主页键） | `com.dangbei.tvlauncher/...MainActivity` | 754KB（当贝桌面） |

日志同步变为：`interceptKeyTi keyCode=3 ... mHomePressed=true deviceName=Hi keyboard`
→ `START u0 {act=MAIN cat=[HOME] cmp=com.dangbei.tvlauncher/...}`。
`event3` 那条路径同样验证通过。

**返回键为什么也没用**：`key 42 BACK` 解析正常（`keyCode=4`），但
`AtvMainActivity` 自己不处理，也不 finish，于是同样落到
`Unhandled key ... keyCode=4, scanCode=42`。TV 信号源界面"无路可退"，属正常行为，
不是故障；修好主页键后不需要返回键。若确实想让返回键回桌面，可把 `key 42` 也改成
`HOME`，但**会破坏所有 app 内的返回键**，不建议。

**踩坑记录**：
- `adb push` 覆盖一个正在被 bind mount 的源文件，`/proc/mounts` 里挂载点会变成
  `...(deleted)`（指向已删除的 inode），看起来还挂着、内容却是旧的。改配置前先
  `umount`，再 push，再 mount。
- 想省事只改 `event3` 那份（`Vendor_046d_...`）没有用，遥控器走的是 `event0`。

### 3.7.3 让电视重启后自己重挂 keylayout（不依赖电脑）★2026-10-18 真重启验证通过

§3.7.2 的 bind mount 重启即失效。要求：**电视端自解决**，不许在 Mac 上挂任何常驻/定时任务，
也不许用悬浮窗（遥控器点不到）。

**先排除掉的路（别再试了）**

| 思路 | 结论 |
|---|---|
| `mount -o remount,rw /system` | `Operation not permitted`（root 下也一样；`/system` 是 `ext4 ro,norecovery` 的 eMMC 分区 `/dev/block/platform/hi_mci.1/by-name/system`，内核不放行） |
| `/data/system/devices/keylayout/` 覆盖 | **无效**：AOSP 查询顺序是 `/system/usr/` **优先**，只有系统侧不存在才回落到 `/data/system/devices/` |
| init 钩子（`/etc/script/*.sh`、`install-recovery.sh`） | 全在只读区：`/etc -> /system/etc`，rootfs 也是 `rootfs ro` |
| `/system/xbin/su` | `-rwsr-x--- root:shell`，第三方 app 不在 shell 组 |
| `/system/xbin/csu` | setuid root 但有 uid 白名单：`uid 10026 not allowed` |

**静态广播其实没被拦**（见下方"广播的真正门槛"），别再往"长虹拦广播"的方向查了。

**突破口**：本机 adbd 以 root 运行且 `ro.adb.secure=0`（不校验 RSA），于是 app 走
`127.0.0.1:5555` 用 adb 协议直接拿到 root shell —— 全程电视内部完成，不需要电脑也不需要 root 权限。
（`MiniAdb.java`：24 字节头 `command/arg0/arg1/data_length/data_check/magic`，
`CNXN → OPEN(shell:) → WRTE/OKAY → CLSE`。）

**触发方式（实测）**

1. **广播。前提是包名不在 `/chperm/preapp/killbackground` 里，且改完要重启（详见下）。**
   满足后 `BOOT_COMPLETED` / `USER_PRESENT` / `SCREEN_ON` / `CONNECTIVITY_CHANGE` /
   `MY_PACKAGE_REPLACED` 全部实测可送达，开机联网阶段就能触发，比 Job 还早一点。
2. **JobScheduler 是兜底**。双任务：
   - `JOB 6511`：一次性 + 自续期，`setMinimumLatency(60s).setOverrideDeadline(120s).setPersisted(true)`，
     每次跑完再排下一次。
   - `JOB 6510`：周期 15 分钟兜底（API 22 允许的最小周期）。

**为什么不能只用周期任务**：周期任务重启后要等整整一个周期才首次执行（实测约 13 分钟）。
而一次性任务的 `deadline` 存的是"绝对时刻"，电视正常开几小时后该值早已过期，
JobScheduler 重启一恢复就判定 overdue，**1~2 分钟内立刻执行**。

**⚠️ 两个必踩的坑**

- `JobService` 的 `android:exported` **必须是 `true`**。写成 `false` 时任务状态一直是
  `READY` 却永远不执行，而且**不报任何错** —— 排查了很久才定位到（JobScheduler 以
  system uid 1000 身份来绑定服务）。
- `adbd 同时只认一个连接`。Mac 连着的时候电视端自连必然 `SocketTimeoutException`，
  所以 `Healer` 里带 8 次重试，每次失败先走一遍三行配方重启 adbd。

**广播的真正门槛：`killbackground` + 必须重启**（2026-10-18 22:33 实测澄清）

一度以为"长虹拦第三方静态广播"——**错的**。真实原因是包名还在 `/chperm/preapp/killbackground`
（后台必杀名单）里，而且这份名单是 **system_server 开机时读一次**的，改完不重启就不生效。

| 时刻 | 事件 | 手动发广播 |
|---|---|---|
| 21:31 | 直接往 `keeprunning`/`AppWhiteList` 写包名（未重启） | ❌ |
| 22:01 | 在电视管家开「自动启动 + 后台运行」→ 系统把包名移出 `killbackground` | ❌（仍未重启） |
| 22:08 | 重装 APK，系统自动发 `MY_PACKAGE_REPLACED` | ❌ |
| 22:22 | 真重启 | — |
| 22:33 | 再手动发 `BOOT_COMPLETED`/`USER_PRESENT`/`SCREEN_ON`/`MY_PACKAGE_REPLACED` | ✅ 全部收到 |

结论：**只写 `keeprunning` 不够，关键是 `killbackground` 里不能有包名，且改完一定要重启。**
排查时别用"手动 am broadcast 收不到"当成"被拦"的证据 —— 先确认是不是还没重启。

**电视管家侧必须开的权限**（用户手动开一次即可，永久生效）：
设置 → 电视管家 → 权限管理 → 自动启动管理 / 后台运行 → 信号源 = 开，**然后重启电视一次**。
它实际写的是 `/chperm/preapp/`：

| 文件 | 作用 | 信号源应在 |
|---|---|---|
| `AppWhiteList` | 应用白名单 | ✅ 在 |
| `keeprunning` | 保活白名单（不在里面的进程被 system_server **keepkilling** 杀掉，日志 `--this one is in keepkilling file ,so kill it--`） | ✅ 在 |
| `killbackground` | **后台必杀 + 连静态广播一起废掉** | ❌ **绝不能在** |
| `popwindowwhitelist` | 悬浮窗白名单 | ✅ 在（已不用悬浮窗，留着无害） |

**真重启验证（2026-10-18 22:2x）**

| 检查项 | 结果 |
|---|---|
| 重启后 `grep -c keylayout /proc/mounts` | **2**（自动恢复，无人工干预） |
| logcat | `[android.net.conn.CONNECTIVITY_CHANGE] 探测挂载数=0` → 重试 → `MOUNTS=2` → `ctl.restart zygote` |
| 切 HDMI1 后 `sendevent /dev/input/event0 1 91` | 前台 `AtvMainActivity` → `com.dangbei.tvlauncher` ✅ |

**副作用**：自愈成功后会 `setprop ctl.restart zygote`（软重启 UI，约 30 秒），
开机后 1~2 分钟内会看到桌面重新加载一次。这是必需的 —— inputflinger 开机时已读过旧键表。

### 3.7.4 自愈跑几小时就失效：fd 泄漏（2026-10-18 23:30 定位并修复）

**现象**：上电视重启验证通过才几小时，主页键又不行了。

```
$ adb shell grep -c keylayout /proc/mounts
0
E/ChSourceHeal: 自愈失败：8 次都没挂上
W/ChSourceHeal: exec 失败 /system/bin/setprop
    Caused by: java.io.IOException: Too many open files
        at java.lang.ProcessManager.exec(Native Method)
        at org.sharmy.chsource.Healer.toggleAdb(Healer.java:161)
```

注意最后一行才是真因：**不是连不上 adbd，是 fd 用光了** —— 连 `setprop` 都 fork 不出来，
自愈彻底瘫掉，而且**自己救不回来**（任何补救都要 exec）。

**根因**：两个地方只关了"外壳"，没关里面的流。

| 位置 | 漏了什么 |
|---|---|
| `MiniAdb.shell()` | `finally` 里只 `s.close()`，`DataOutputStream` / `DataInputStream` 各自的 fd 没关 |
| `Healer.exec()` | `Runtime.getRuntime().exec()` 出来的 `Process`，三个 pipe（stdin/stdout/stderr）全没关 |

app 进程的 fd 上限是 **1024**。原先每 60~120 秒一轮、每轮最多 8 次连接 + 3 次 `setprop`
（`toggleAdb`），一小时就是几百个 fd —— **几小时必然耗尽**。

**修复（4 处）**

1. `MiniAdb`：`out` / `in` / `s` **三个都关**，且 `out`、`in` 要提到 `try` 外声明。
2. `Healer.exec()`：`p.getOutputStream()/getInputStream()/getErrorStream()` 全部 `close()`，
   再 `waitFor()`，最后 `p.destroy()`。
3. `copyAsset()` / `writeScript()`：文件流改 `try/finally`。
4. **探测不再走 adb**：判断"挂上了没有"直接读 `/proc/mounts`（全局可读，**不需要 root**）。
   常态（已挂载）**零 adb 连接**，只有真掉了才去连 adbd。

**顺带降频**

- 已挂载 → 下次巡检 4~6 分钟（本地读，成本≈0）；未挂载 → 60~120 秒高频重试。
- `toggleAdb()` 改成**隔一轮**才重启 adbd（原来 8 次就是 40 秒，还会把电脑上的 adb 踢掉）。
- 每次日志带 `fd=N`，一眼能看出有没有再泄漏（正常值 ~30）。

**验证（2026-10-18 23:4x）**

| 步骤 | 结果 |
|---|---|
| 手工 `umount` 掉两个 bind mount（模拟重启后状态） | `MOUNTS=0` |
| `adb disconnect`（把连接位让出来）后等 170 秒 | `MOUNTS=2` ✅ 电视自己接回来了 |
| `sendevent /dev/input/event0 1 91` | `START u0 {act=MAIN cat=[HOME] cmp=com.dangbei.tvlauncher/...}` ✅ |
| `fd` | 29（健康） |

**顺带两个坑**

- 用 `ssh`(2222) 跑 `am` 必须加 **`--user 0`**，否则：
  `SecurityException: startActivity asks to run as user -2 but is calling from user 0`。
  （`adb shell` 是 shell 用户，无此问题；`admin=u0_a26` 会撞上。）
- **SimpleSSHD 不是常驻的**，电视重启后要在电视上手动打开一次，否则 2222 直接
  `Connection refused`。
- `adb install -r` 之后系统会 `Force stopping ... pkg changed`，进程被杀，
  `MY_PACKAGE_REPLACED` 不会送达 → **装完必须手动启动一次 app**，让它把 Job 重新注册上。

### 3.7.5 挂载数是 2、主页键却没反应：框架没重启，键表没重载 ★2026-10-27 定位并修复

**现象**：`grep -c keylayout /proc/mounts` = **2**（自愈明明成功了），但按主页键毫无反应。
`input keyevent 3` 却能正常回当贝 —— 说明 HOME 意图链路没问题，卡在
**scan 91 → keycode 的转换**上。

**根因**：keylayout 是 **inputflinger 在打开设备那一刻读进内存的**，之后改文件它不会重读。
而本机 **inputflinger 不是独立进程**：

```
$ getprop init.svc.inputflinger   → 空
$ ps | grep inputflinger          → 无
```

它跑在 **system_server 进程里**，所以只有把框架（system_server）重启了才会重新加载键表。
自愈里那句 `setprop ctl.restart zygote` **发出去了但没生效** —— 自愈在开机早期跑，
此时还没 `bootcomplete`，init 直接把 `ctl.restart` 给忽略了。

**硬判据**（别靠"感觉"）：看 system_server 的启动时刻有没有变。

```bash
SS=$(adb shell ps | grep system_server | awk 'NR==1{print $2}')     # pid
adb shell awk '{print $22}' /proc/$SS/stat                          # starttime(tick)
```

出事那次：pid=1985、starttime=754（开机 7.5 秒启动），uptime 已经 2800 秒了 ——
**框架从头到尾没重启过**，那挂载得再漂亮也没用。

**修复（APK 侧，Healer）**

1. 挂载成功后不能算完，还得**重启框架**，并把"挂载 OK 但框架没重启成功"这个状态
   持久化（`K_PENDING`），下一轮接着重启，避免一次失败就永久卡住。
2. 重启**之前先等 `dev.bootcomplete=1`**（最多 2 分钟）—— 开机早期发 `ctl.restart`
   会被 init 忽略，这是这次白干一场的直接原因。
3. 重启**必须校验**：对比 `system_server` 的 `pid:starttime` 是否真的变了。
   - 先客气：`setprop ctl.restart zygote`
   - 15 次 × 5 秒没变 → `kill -9 <system_server pid>`（zygote 发现它死了会自杀，
     init 重新拉起，等于完整软重启）
4. 检测到变化的**第一时间**就把 `pending` 落盘 —— app 进程马上会被 zygote 重启杀掉，
   晚一点就丢，下一轮会白重启一次（用户看得见画面重载两回）。

`65d2p.sh fix-keys` 同步加固（原来也是裸发 `ctl.restart`）：发完轮询 90 秒看 pid 变没变，
没变就 `kill -9` 兜底。

**验证（2026-10-27 22:3x）**：手工 `umount` 掉两个 bind mount → Mac 侧 `adb kill-server`
把连接位让出来 → 5 分钟内电视自己完成：挂载数回 2、`system_server` 5158→9615（真重启了）、
`sendevent /dev/input/event0 1 91` 触发 `START u0 {act=MAIN cat=[HOME]}` ✅

**顺带三个坑**

- **Mac 断开 adb 要用 `adb kill-server`**，只 `adb disconnect` 不够：adb server 还占着
  adbd 唯一的连接位，电视端自连会一直 `SocketTimeoutException`（实测 8 次全超时）。
- **重装 APK 会把包名重新写回 `/chperm/preapp/killbackground`**：
  `PackageManager: --this one is not protect app---so killbackground&prevent receiver`。
  即电视管家里的白名单会被安装动作冲掉，装完要重新处理一次（root 下
  `grep -v 包名` 重写该文件，再重启生效）。
- `/tmp` 被系统清过后，构建链要重装：`platform-tools`、`build-tools_r33.0.1-macosx`、
  `platform-30_r03`、JDK 17（国内可用腾讯 Kona）。
  `hdmi1/build.sh` 已改成自动探测并在缺件时直接打印下载命令。

### 3.7.6 别用「我重启过没有」当标志：app 会被自己发起的重启杀掉 ★2026-10-27

§3.7.5 第一版实现用了"挂载 OK 但框架没重启 → 记 `pending`，下轮接着补"。
**这个标志永远清不掉**：`ctl.restart zygote` 会把 zygote 的所有子进程一起杀掉，
本 app 就在里面 —— 进程没了，那句 `commit()` 根本来不及执行。

后果很直观：每 4~6 分钟重启一次框架，**电视画面反复重载**。止血是 root 下直接改
`/data/data/org.sharmy.chsource/shared_prefs/heal.xml`（电视没有 `sed`，用
`busybox sed -i`）。

**正确判据：比较时刻，不看自证标志。**

```
system_server 启动时刻(秒) > 本次 keylayout 挂载时刻(秒)  →  键表已生效
```

- 挂载成功时记 `mount_uptime = SystemClock.elapsedRealtime()`
- `system_server` 的启动时刻取 `/proc/<pid>/stat` 第 22 字段（clock tick，本机 USER_HZ=100）
- 确认后记 `confirmed=true`，之后**零 adb 连接**（挂载时刻和启动时刻都在本地/一次读取内）
- 判断不了（读不到 ps）就**本轮不动**，绝不能"猜"着重启 —— 那比不修更烦人

**两个附带坑**

- `ps | grep system_server` 必须加 `grep -v grep`：shell 命令行里也含这个字符串，
  `ps` 会把 grep 自己列出来，`NR==1` 可能取到它的 pid，而它读完就退出了，
  `/proc/<pid>/stat` 已不存在 → 读出空值 → 表现成"无法判定"。
- 电脑连着 adb 时，电视端自连 `127.0.0.1:5555` 必然超时，所有这类探测都会失败。
  排查时看到 `ss=-1` 先想想自己是不是还占着连接位（要 `adb kill-server`）。

### 3.7.7 长虹禁止第三方自启：进程一死就再也拉不回来 → 必须前台服务保活 ★2026-10-27

**现象**：自愈测通之后过几十分钟又失效。查下来 app 进程**已经不存在了**，
而系统里 Job 还挂着、闹钟也还在。

**三条路实测结果**

| 拉起方式 | 结果 |
|---|---|
| `JobScheduler` | ❌ Job 在系统里 overdue 1 分 50 秒，4 分钟内**一次都没执行**；手动 `am start` 把 app 叫起来后，它立刻连跑两次 |
| `AlarmManager.setRepeating` | ❌ `dumpsys alarm` 里明明有 `1 wakeups`（闹钟确实触发了），但 `BroadcastReceiver.onReceive` **压根没被调用**，日志一片空白 |
| `BOOT_COMPLETED` 等开机广播 | ✅ 能拉起，但一次开机只来一次 |
| 从 adb 发 `am broadcast` | ✅ 立刻拉起（shell/root 身份，走的是另一条路） |

结论：**长虹禁止第三方 app 自启动**，只放行开机广播那一类。

**由此产生的死锁**

```
自愈要让键表生效 → 必须重启框架 → 框架重启把本 app 一起杀掉
                → 之后没有任何机制能拉起它 → 下次 bind mount 丢了就永久失效
```

这就是"修好一次、过几十分钟又不行"的真正原因。

**解法：别让进程死**

`KeepAliveService` —— 前台服务（`startForeground`），优先级足够高，躲得过 LMK
和普通后台清理；再加 `START_STICKY`，万一被杀系统会重建。服务里用
`HandlerThread` 每 3 分钟跑一次 `Healer.run`，Job/闹钟保留作兜底。

由 `BootReceiver`（每次收到广播）和 `SwitchActivity`（用户点图标）负责拉起。

**验证（2026-10-27 23:5x）**

| 步骤 | 结果 |
|---|---|
| 手工 `umount` 两个 bind mount | 挂载数 0 |
| `adb kill-server` 后完全不管 | 4 分钟内自动完成 |
| `system_server` | 3903 → **6742**（框架自己重启了） |
| 日志 | `system_server 启动于开机后 1248s，晚于挂载时刻 1245s → 键表已生效` |
| app 进程 | **8038 仍在**（框架重启后自己回来了） |
| `sendevent 91` | HOME 意图触发，前台是当贝 ✅ |

**副作用**：前台服务会挂一条常驻通知（"主页键守护运行中"）。电视上一般看不到
通知栏，影响很小；但这是长虹这种限制下唯一的办法。

### 3.8 自定义开机画面（把开机图换成自己的照片）★2026-10-18 22:45 实机验证通过

既然 §3.6 已经把开机广告根除，开机那几秒空出来了 —— 可以拿来放自己的照片。

**机制**：这跟广告是**两条独立的路**，互不影响。

```
ro.third.str.logo.path  = /chperm/logo/media/STRbootlogo.png   ← 静态开机图（我们要换的）
                            └─ 软链 → /data/logo/media4/STRbootlogo.png（可写分区）
ro.third.bootvideo.path = /chperm/logo/media/video.ts          ← 开机视频/广告（已清空 + immutable）
```

`/system/bin/bootanimation` 开机进 **STR 模式**直接画那张 PNG。logcat 实证：

```
I/BootAnimation: BootAnimation goto STR mode
I/BootAnimation: start to draw strbootlogo, file: /chperm/logo/media/STRbootlogo.png
I/BootAnimation: draw strbootlogo end , wait exit
```

（`strings /system/bin/bootanimation` 里还有 `no default str logo, exit`、
`persist.sys.logo.time`、`debug.sf.nobootanimation`，逻辑一目了然。）

**素材规格**（从原厂 PNG 的 IHDR 反推）：

| 项 | 值 |
|---|---|
| 尺寸 | **1920 × 1080** |
| 位深 / 色彩 | 8bit、**RGB（color type 2，不要 alpha）** |
| 格式 | PNG |
| 显示时长 | `persist.sys.logo.time`（秒，persist 属性，重启保留） |

⚠️ `persist.sys.logo.time` 当初为了灭广告被设成了 `0` —— 不把它调成非 0，
换了图也只是一闪而过。默认给 8 秒。

**做法（一步到位）**：

```bash
./65d2p.sh bootlogo ~/Pictures/我家.jpg        # 默认显示 8 秒
./65d2p.sh bootlogo ~/Pictures/我家.jpg 5      # 自定义秒数
```

脚本会：等比裁剪铺满到 1920×1080 RGB PNG → push 到 `/data/logo/media4/STRbootlogo.png`
→ `chmod 644` → `setprop persist.sys.logo.time 8`。
**重启生效**。原厂图在换图前只备份一次（电视 `/data/local/tmp/logo_backup/STRbootlogo.orig.png`），
避免把上一张自定义图误当备份。

```bash
./65d2p.sh bootlogo-restore    # 还原长虹原厂开机图
./65d2p.sh bootlogo-test       # 不重启，就地拉起一次开机画面看效果（几秒后自动停）
```

**裁剪策略**：默认 **cover**（等比缩放后居中裁剪，铺满无黑边）。竖构图的照片会裁掉上下，
想完整保留画面就先在电脑上裁成 16:9 再喂进来。

**注意**：`bootlogo-test` 会把电视屏幕覆盖几秒，属正常；脚本结束时会
`setprop service.bootanim.exit 1` + `ctl.stop bootanim` 自动恢复。
若中途 adb 断连导致画面卡住，重连后执行这两条即可恢复。

**传文件的三个坑（都踩过，已在脚本里处理）**

1. **别用 adb 传 3MB 文件**。adbd 只有一个连接位，电视端自愈任务 `Healer` 一旦在重试
   就会来抢，把 Mac 的会话挤掉 —— 表现为传到一半 `failed to read copy response: EOF`
   + `device offline`。**改走 SimpleSSHD(2222)**，没有这个限制。
   （§3.7.4 之后 Healer 常态已不连 adbd，只在挂载真掉了才连，冲突概率小多了。）
   实测 admin(`u0_a26`) 权限够用：
   - `/data/logo/media4/` 是 `drwxrwxrwx`（777），能写
   - `setprop persist.sys.logo.time` 也能设
   - 但 `/data/local/tmp` 是 `shell:shell 771`，**读不了**（备份要放 `/sdcard`）
2. **目标文件是 `root:root 644`，admin 只能"删了重建"**，不能直接覆写（scp 会
   permission denied）。正确顺序：`rm -f` → `scp` → 新文件 owner 变成 u0_a26、644，
   root 照样能读。
3. **电视的 sh 极度精简**：没有 `wc`、`stat`、`head`、`tail`、`strings`。
   数文件大小只能用 `busybox wc -c`（注意它输出带路径，要 `awk '{print $1}'` 取第一列，
   否则路径里的 `/media4/` 那个 4 会混进数字）。
   另外它的 `ls -l` 输出**没有 links 列**（不是标准 9 列），`awk '{print $5}'` 会取到日期。

**校验才是重点**：脚本先传、再比字节数，通过才覆盖开机图。直接覆盖的话，
一旦传一半断掉，`STRbootlogo.png` 就是个截断的 PNG —— 开机黑屏或坏图。

## 4. C. 封死 OTA（三层）

### 层 1 — 光猫网址过滤（网络层，已配置）
管理页 `192.168.1.1` → 安全 → 广域网访问设置 → 网址过滤 → **黑名单**，逐条「新建」后点「应用」：

```
huan.tv    upgrade2    smart-tv    chsmarttv    hifuntv    chiq-cloud
```

⚠️ 别加 `ads`、`umeng` 这类短词，会误伤全家设备。
⚠️ 该过滤**只对 HTTP 明文生效**，HTTPS 走 SNI 绕不过去（实测 `https://ads.huan.tv` 仍能通）。

### 层 2 — 禁用升级组件（系统层，最有效）
```bash
./65d2p.sh ota-lock
```
禁用：`com.changhong.systemupgrade`、`com.changhong.dmt.upgrade`、`com.changhong.upgrade`、`com.changhong.upgradechiq`

### 层 3 — hosts（✅ 已落地，用 bind mount 绕过只读）
`mount -o remount,rw /system` 返回 `Operation not permitted`（SELinux 已是 Disabled，
不是它挡的；`/system` 是 `ext4 ro,norecovery`，内核侧不放行 rw 重挂）。

**但 bind mount 是可以的** —— `/data` 上写一份新文件，直接挂到 `/system` 里的目标路径上
（详见 §3.6 与 §3.7.2）：

```bash
adb exec-out sh -c "chmod 644 /data/local/tmp/hosts; \
  mount -o bind /data/local/tmp/hosts /system/etc/hosts"
```

局限：**bind mount 重启即失效**，已并入 `./65d2p.sh fix-adb` 的开机必跑流程。

**实际效果：层 1 + 层 2 已足够**，电视「检查更新」失败。

## 5. B. 换桌面（顺序不能反）

1. **先装当贝桌面**（包名 `com.dangbei.tvlauncher`）—— 当贝市场里搜，或 `./65d2p.sh install xxx.apk`
2. **再禁用长虹桌面**：
```bash
./65d2p.sh switch-home
# 内部：am start HOME → pm disable com.changhong.system.launcher.v2 → 验证前台
```
3. 回滚：`./65d2p.sh restore-home`

## 6. 回滚（全部可逆）

```bash
./65d2p.sh restore        # 恢复所有广告包 + 升级组件
./65d2p.sh restore-home   # 恢复长虹桌面
# 单个恢复： adb exec-out sh -c "pm enable com.changhong.spanner"
```

## 7. 已知限制（别再踩）

- **`/system` 无法 remount 读写** → hosts / 开机广告 / 彻底卸载预装 都做不了
- **电视 shell 极简**：无 `sed` `grep` `head` `wc` `whoami`，一律走 `/system/bin/busybox sed|grep|sort|wc`
- **本机网络限制**：APKMirror / APKPure / F-Droid 均不可达，只有 GitHub 和 `dl.google.com` 通
- **U 盘装 APK 报"解析包时出现问题"**：与 APK 无关（yecao.apk 实测 minSdk 17 / targetSdk 22 / v1 签名 / armeabi-v7a 全兼容），
  是 U 盘或安装器问题 → **改用 `adb install`，已验证可用**

## 8. 常用命令速查

```bash
./65d2p.sh status                 # 状态总览
./65d2p.sh pkgs                   # 第三方 / 已禁用列表
./65d2p.sh install /path/x.apk    # 装应用（不再需要 U 盘）
./65d2p.sh shell "pm list packages -s"   # 任意 root 命令
adb exec-out sh -c "dumpsys window windows | /system/bin/busybox grep mCurrentFocus"  # 看当前前台界面
```

## 9. 安全说明

- ADB 免认证 root shell，局域网内任何人可完全控制电视。
- **用户已决定保持常开**（家里无访客）。需要时：
```bash
关： adb exec-out sh -c "setprop service.adb.tcp.port -1"
开： adb exec-out sh -c "setprop persist.adb.tcp.port 5555; stop adbd; start adbd"
```
