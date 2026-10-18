# 长虹 65D2P 信号源一键切换 APK

桌面上放图标，点一下直接切到 HDMI1（机顶盒）/ HDMI2 / DTV / AV，
或弹系统信号源菜单，或**从 HDMI 切回安卓系统桌面**。
适用：长虹 65D2P（机芯 ZLH74GiR，V1.00039，Android 5.1.1，HiSilicon hi551）。
其他长虹机芯大概率通用（只要 `/system/framework/com.changhong.tvos.jar` 存在）。

## 切到 HDMI 后怎么回到安卓系统

**先修系统设置（一劳永逸）**：

```bash
adb exec-out sh -c "settings put secure user_setup_complete 1; settings put global device_provisioned 1"
# 或：../65d2p.sh fix-home
```

修完遥控器「主页」键即可正常回到当贝桌面。

**为什么必须修**：本机 `user_setup_complete=0`、`device_provisioned=0`，
`ActivityManagerService.startHomeActivityLocked()` 认为「用户设置未完成」，
**静默拒绝启动桌面**，只在 logcat 留一条：

```
I/WindowManager: Not starting activity because user setup is in progress: Intent { act=MAIN cat=[HOME] ... }
```

所以按键 HOME 无效，而 `am start -a MAIN -c HOME` 有效（两者走的检查不一样）。
「回到系统桌面」图标就是发 HOME intent，可作为主页键的备用入口。

⚠️ 别去信号源菜单里找「Android / 智能系统」——本机 `getInputSourceList()` 实测只有
ATV / DTV / CVBS / HDMI1 / HDMI2，**没有回系统的信号源项**。回系统是前台 Activity 切换。

## 原理

系统把 `com.changhong.tvos.jar` 放进了 `BOOTCLASSPATH`（见 `/init.environ.rc`），
因此**任意第三方 app 都能反射调用长虹私有 TVOS SDK**，无需系统签名：

```java
TVManager.getInstance(ctx)      // com.changhong.tvos.common.TVManager
    .getATVPlayer()             // com.changhong.tvos.atv.IATVPlayer
    .startInputSource(EnumInputSource.E_INPUT_SOURCE_HDMI, 15);
```

这与系统「信号源」菜单 `com.changhong.SourceMenu → MenuSource.changeSource`
内部使用**同一句代码**（反汇编 `SourceMenu.apk` 可证）。

## 目录结构

```
hdmi1/
├── AndroidManifest.xml                       # 1 个 Activity + 6 个 activity-alias + 2 service + 1 receiver
├── src/org/sharmy/chsource/
│   ├── SwitchActivity.java                   # 反射 TVOS SDK 切源 / 回桌面 / 调试指令
│   ├── HomeUtil.java                         # 统一的"回桌面"实现（Activity 与 Service 共用）
│   ├── MiniAdb.java                          # 极简 adb 协议客户端（连本机 root adbd）
│   ├── Healer.java                           # 自愈逻辑 + JobScheduler 注册
│   ├── HealJobService.java                   # JobService 执行体
│   ├── SelfHealService.java                  # IntentService 执行体（广播触发时用）
│   ├── BootReceiver.java                     # 多广播触发（BOOT/USER_PRESENT/SCREEN_ON/网络…）
│   └── …
├── assets/Vendor_*.kl                        # 修复版 keylayout（打包进 APK）
├── res/drawable-nodpi/ic_*.png               # 图标（Pillow 生成）
├── keylayout/                                # 同上的副本 + 原厂备份 + fixkeys.tv.sh
├── build.sh                                  # 手工构建脚本（不用 Gradle）
└── build/信号源切换-HDMI1.apk                # 产物
```

一个 Activity + 多个 `activity-alias`，每个 alias 用
`<meta-data android:name="source" android:value="E_INPUT_SOURCE_HDMI">`
声明目标源 → 一份代码出多个桌面图标。

调试指令（`am start -n org.sharmy.chsource/.Home --es source XXX`）：

| source | 作用 |
|---|---|
| `__LIST__` | 列出本机支持的信号源与当前源 |
| `__MENU__` | 弹系统原生信号源菜单 |
| `__HOME__` / `__SYS__` | 回安卓桌面 |
| `__HEAL__` | 立即触发一次自愈（不用重启也能验证） |
| `__ADB__` | 用 `--es cmd "id"` 验证 app 能否拿到 root shell |

## 构建

需要 **JDK 17** 与 **aapt2 / d8 / zipalign / apksigner**。
`build.sh` 默认到 `/tmp/android` 找工具链，按实际路径改脚本头部即可。

```bash
# 工具链（只需准备一次）
curl -sL -o /tmp/android/jdk17.tar.gz \
  "https://api.adoptium.net/v3/binary/latest/17/ga/mac/aarch64/jdk/hotspot/normal/eclipse"
cd /tmp/android && tar xzf jdk17.tar.gz
curl -sL -o bt.zip https://dl.google.com/android/repository/build-tools_r33.0.1-macosx.zip
curl -sL -o plat.zip https://dl.google.com/android/repository/platform-30_r03.zip
unzip -q bt.zip -d bt_t && unzip -q plat.zip -d plat_t

# 构建
cd hdmi1 && ./build.sh
```

签名密钥在 `keystore/chsource.jks`（首次自动创建，务必保留，否则后续安装会
`INSTALL_FAILED_UPDATE_INCOMPATIBLE`）。

## 安装与验证

```bash
adb install -r build/信号源切换-HDMI1.apk

# 若 Toast 报 SecurityException: writing to settings
adb exec-out sh -c "pm grant org.sharmy.chsource android.permission.WRITE_SETTINGS"

# 命令行直接切（不点图标）
adb exec-out sh -c "am start -n org.sharmy.chsource/.Hdmi1"

# 查本机支持哪些信号源 / 当前是哪个
adb exec-out sh -c "am start -n org.sharmy.chsource/.Hdmi1 --es source __LIST__"
adb exec-out sh -c 'logcat -d | /system/bin/busybox grep I/ChSourceSwitch'
```

## 切到 HDMI 之后怎么回系统（主页键）

**别指望遥控器主页键直接能用** —— 本机有两个坑，都得填：

1. `Settings.Secure.user_setup_complete=0` → 系统"静默拒绝"启动桌面
   → `../../65d2p.sh fix-home`
2. 主页键扫描码 91 在 keylayout 里被映射成 `CHANGHONGIR_HOME`（本机框架无此 keycode，
   解析成 `keyCode=0` 被丢弃）→ `../../65d2p.sh fix-keys`

第二项靠 bind mount 覆盖 `/system/usr/keylayout/`（只读，remount 被拒），
**重启即失效**。细节见 runbook §3.7.1 / §3.7.2。

`keylayout/` 目录就是这份修复的版本，`Vendor_0001_Product_0001.kl.orig` 是原厂原件备份。

APK 里的「回到系统桌面」图标（`__SYS__`）仍保留，作为不依赖按键的备用入口。

### 重启后自动重挂（已内置，2026-10-18 真重启验证通过）

不再需要电脑重跑 `fix-keys`：APK 自己会在开机后 1~2 分钟内把 keylayout 重新挂上。

做法：本机 adbd 以 root 运行且 `ro.adb.secure=0`，app 直接走 `127.0.0.1:5555`
用 adb 协议拿 root shell（`MiniAdb.java`，约 120 行的极简 adb 客户端），
再 `mount -o bind` + `setprop ctl.restart zygote`，全程电视内部完成。

触发靠 JobScheduler（`Healer` / `HealJobService`）：

| JOB | 类型 | 作用 |
|---|---|---|
| 6511 | 一次性 + 自续期，60~120s | 主力。deadline 是绝对时刻，开几小时后早已过期，重启一恢复就 overdue 立刻执行 |
| 6510 | 周期 15 分钟 | 兜底（API 22 最小周期） |

顺带监听 `BOOT_COMPLETED` / `CONNECTIVITY_CHANGE` / `USER_PRESENT` / `SCREEN_ON` 等广播做
"早起"触发 —— 前提是包名**不在** `/chperm/preapp/killbackground` 里（在电视管家开
「自动启动 + 后台运行」即可），**而且改完要重启一次**才生效：这份名单是 system_server
开机时读一次的，不重启的话所有静态广播都送不到（容易误判成"被系统拦了"）。

⚠️ 两个坑：`JobService` 的 `android:exported` **必须是 `true`**（写成 false 会一直 READY
但永不执行，且不报错）；`adbd` 同时只认一个连接，电脑连着时电视端必然超时，所以带 8 次重试。

⚠️ 电视管家 → 权限管理 → 自动启动管理 / 后台运行 → 给「信号源」打开，**然后重启电视一次**。
它写的是 `/chperm/preapp/{AppWhiteList,keeprunning,popwindowwhitelist}`，并把包名从
`killbackground`（后台必杀）里移除；这份名单 system_server 开机只读一次，**不重启不生效**。

⚠️ 副作用：自愈成功后会软重启 zygote，开机 1~2 分钟内桌面会重新加载一次。

## 逆向备忘（别再重复摸索）

| 项 | 值 |
|---|---|
| SDK jar | `/system/framework/com.changhong.tvos.jar` |
| 服务 | `ServiceManager.getService("CHTVService")` → `ITVService`（system_server） |
| 切换 API | `ITVPlayer.startInputSource(EnumInputSource, int)` → boolean，第二参被 `PlayerImpl` 忽略 |
| 备用 API | `ISourceManager.selectInputSource(EnumInputSource)` |
| 读回校验 | `ISourceManager.getCurInputSource(EnumPipInputSource.E_MAIN_INPUT_SOURCE)` |
| 枚举序号 | ATV=0, DTV=1, CVBS=2…, **HDMI=19**, HDMI2=20, HDMI3=21, HDMI4=22（共 35 个） |
| 本机实测支持 | **ATV, DTV, CVBS, HDMI1, HDMI2**（无 HDMI3） |
| 坑 1 | `TVManager.getInstance(Context)` —— 必须带 Context，无参版不存在 |
| 坑 2 | 切源写 `Settings.System` → 需 `WRITE_SETTINGS` |
| 坑 3 | 切完系统会拉起 `com.changhong.tvap.atv.activity.AtvMainActivity`（正常现象） |

反汇编用的是纯 Python 自写的 dex 解析器（`dexdump.py` 思路）：解析 header →
string_ids / type_ids / proto_ids / field_ids / method_ids / class_defs →
class_data_item → code_item → 指令流。本机没有 JDK/SDK 时靠它把接口挖出来。
