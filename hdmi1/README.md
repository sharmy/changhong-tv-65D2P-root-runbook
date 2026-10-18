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
├── AndroidManifest.xml                       # 1 个 Activity + 6 个 activity-alias
├── src/org/sharmy/chsource/SwitchActivity.java
├── res/drawable-nodpi/ic_*.png               # 图标（Pillow 生成）
├── build.sh                                  # 手工构建脚本（不用 Gradle）
└── build/信号源切换-HDMI1.apk                # 产物
```

一个 Activity + 多个 `activity-alias`，每个 alias 用
`<meta-data android:name="source" android:value="E_INPUT_SOURCE_HDMI">`
声明目标源 → 一份代码出多个桌面图标。

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
