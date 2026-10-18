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

### 层 3 — hosts（❌ 做不到，已尝试）
`mount -o remount,rw /system` 返回 `Operation not permitted`。
排查结论：SELinux **已是 Disabled**，busybox mount 也报 `permission denied (are you root?)`
→ **adbd 的 capabilities 被内核限制**（uid=0 但没有 CAP_SYS_ADMIN）。
所以 `/system` 改不了，hosts、去开机广告、彻底卸载预装都做不了，除非刷机改包。

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
