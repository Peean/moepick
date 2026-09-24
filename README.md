# 拾萌 (MoePick)

表情包 / 贴纸管理应用。按「系列」组织表情包,支持分类、标签、备注三级元数据与全文检索,内置主题定制、自定义背景、本地备份与 WebDAV 多端同步。

- **包名 / 应用 ID**:`moepick`(显示名:拾萌)
- **技术栈**:Flutter 3.0.0 / Dart 2.17,Riverpod 2.3(手写 Notifier),go_router 4.5,Hive 2.2
- **目标平台**:Android 为主,附带 Windows 与 Linux 桌面端(无 Web 端)

## 功能

| 功能 | 说明 |
|---|---|
| 主题色 | 8 种预设种子色,明/暗/跟随系统三种模式 |
| 自定义背景 | 卡片式 / 全屏两种模式;不透明度、遮罩颜色与浓度、模糊强度均可调;模糊在 isolate 中预渲染并缓存,不占帧预算 |
| 系列管理 | 表情包归属系列;系列与单张表情包均可设分类、标签、备注 |
| 元数据继承 | 分类:表情包**覆盖**系列;标签:系列 **∪** 表情包;备注:以 ` · ` 拼接;显示名回退系列名 |
| 搜索 | 按分类、标签、备注、名称检索,可在结果页直接跳转 |
| 备份 | 应用设置单独导出;完整备份(数据库 + 图片 + 设置)为本地 zip;从 zip 一键恢复 |
| WebDAV 同步 | 单 zip 快照 + `.meta.json` 指纹比对,启动时与周期性自动同步;删除以墓碑记录传播 |

## 目录结构

```
lib/
  core/           常量、错误、存储(Hive/文件/安全存储)、主题、工具
  data/           模型与仓储(Hive 实现 + EffectiveMeta 继承语义)
  features/
    library/      库页(系列网格)
    series/       系列详情 / 编辑
    sticker/      表情包详情 / 编辑
    search/       搜索页
    settings/     设置中心、主题、背景、分类标签管理、备份、WebDAV
    backup/       备份打包与恢复
  sync/           WebDAV 同步引擎
  routes/         go_router 配置
  shared/         通用组件(背景层、输入对话框、贴纸瓦片等)
test/             单元 / widget / 回归测试
tool/             Linux 构建与运行辅助脚本
```

## 环境要求

- Flutter 3.0.0(Dart 2.17;更高版本亦可,但 `pubspec` 锁定于该工具链验证过的依赖)
- Java:OpenJDK 17(Gradle 7.4 不支持 Java 18+;`JAVA_HOME` 指向 17)
- Android:SDK 21+;Windows:Visual Studio 2022 桌面 C++ 工作负载;Linux:GTK 3 开发库、`ninja-build`、`cmake`
- Linux 运行时另需 `xdg-user-dirs` 包(提供 `xdg-user-dir` 可执行文件);缺失时 `path_provider` 无法解析 `~/Documents`,应用会按设计显示「启动失败」而非崩溃

## 应用图标

图标为「贴纸笑脸」:樱粉渐变底(与应用默认种子色 `#E38FB1` 一致)+ 白描边呆毛圆脸。资源同时包含:

- `mipmap-*/ic_launcher.png` / `ic_launcher_round.png`:传统图标(48dp 基准)
- `mipmap-*/ic_launcher_foreground.png` + `drawable/ic_launcher_background.xml` + `mipmap-anydpi-v26/ic_launcher.xml`:Android 8+ 自适应图标(前景 108dp 基准,内容收在中央 66% 安全区)
- `android/playstore-icon.png`:商店 512px 图

修改配色或形状后重新生成:

```bash
pip3 install pillow
python3 tool/gen_icons.py
```

## 构建与运行

```bash
flutter pub get

# Android
flutter build apk            # 调试: flutter run
flutter build appbundle      # 商店 AAB

# Windows
flutter config --enable-windows-desktop
flutter build windows

# Linux
flutter config --enable-linux-desktop
./tool/build_linux.sh        # 见下方说明
./tool/run_linux.sh 20       # 无显示器环境用 xvfb-run 拉起
```

> Android 构建参数:`compileSdk 33`、`minSdk 18`、`Kotlin 1.9.10`。后两项高于 Flutter 3.0 模板默认值,是 `desktop_drop`(Kotlin 1.9.10)与 `flutter_secure_storage`(minSdk 18)插件的硬性要求,已在 `android/app/build.gradle`、`android/build.gradle` 中固定。

### 中国大陆网络构建

沙箱/国内网络无法直连 `dl.google.com`、`repo.maven.apache.org`、`services.gradle.org`、`storage.googleapis.com`,需两处镜像配置:

1. **Gradle 仓库镜像**(`tool/mirror-init.gradle`):复制到 Gradle 用户目录的 init 目录,Gradle 会自动加载,把阿里云镜像前置到每个插件声明的 `google()`/`mavenCentral()` 之前:

   ```bash
   cp tool/mirror-init.gradle "$GRADLE_USER_HOME/init.d/"   # 或 ~/.gradle/init.d/
   ```

2. **`flutter.gradle` 镜像补丁**:`flutter_tools/gradle/flutter.gradle` 顶层 `buildscript` 是独立作用域,init 脚本管不到,需手动在其 `repositories` 前置:

   ```gradle
   maven { url 'https://maven.aliyun.com/repository/google' }
   maven { url 'https://maven.aliyun.com/repository/public' }
   ```

3. **Gradle 发行版**:首次运行 `./gradlew` 会从 `services.gradle.org` 下载发行版,国内可用 `https://mirrors.cloud.tencent.com/gradle/gradle-7.4-all.zip` 替换 `gradle-wrapper.properties` 的 `distributionUrl`,或先手动下载放入 wrapper 缓存目录。

### Linux 构建说明(`tool/build_linux.sh`)

Flutter 3.0 的 Linux CMake 工程把 `INSTALL_PREFIX` 固定为 `/usr`,直接 `flutter build linux` 后 `ninja install` 会试图写系统目录。脚本绕过方式:

```bash
cd build/linux/x64
cmake . -DCMAKE_INSTALL_PREFIX="$PWD/bundle"
ninja && ninja install
```

产物在 `build/linux/x64/debug/bundle/moepick`(或对应 release 目录)。

### Linux 运行时依赖

```bash
sudo apt-get install -y xdg-user-dirs
```

应用数据根目录为 `~/Documents/moepick`(经 `path_provider` 解析,数据库只存相对路径,换设备恢复备份后仍有效)。

## 测试与静态检查

```bash
flutter analyze   # 当前 0 issue
flutter test      # 101 个测试
```

测试分层:

- `test/data/` EffectiveMeta 继承语义(分类覆盖 / 标签并集 / 备注拼接)
- `test/storage/` Hive 仓储、备份打包恢复、防抖等(45 个)
- `test/shared/` `contextIsAlive` 守卫与文本对话框 controller 生命周期回归
- `test/app_smoke_test.dart` 真实挂载应用:启动、持久化、主题预设、路径覆盖

## 发布检查清单

### Android

1. `android/app/build.gradle`:`applicationId` 保持 `com.moepick.moepick`,按渠道调整 `versionCode` / `versionName`
2. `flutter build appbundle --release` 生成商店用 AAB;`flutter build apk --release` 生成直装 APK(输出于 `build/app/outputs/flutter-apk/`)
3. 签名:模板默认用 debug key,发布前配置正式签名——生成 keystore 后在 `android/key.properties` 写入路径与口令,并在 `app/build.gradle` 的 `buildTypes.release` 引用:

   ```bash
   keytool -genkey -v -keystore ~/moepick-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias moepick
   ```

4. 权限最小化:确认 `AndroidManifest.xml` 只声明实际用到的权限(网络仅 WebDAV 同步需要)
5. 目标 API 级别满足商店当年要求;真机回归:备份导出分享、从文件恢复、WebDAV 同步
6. 桌面显示名与图标:`android:label="拾萌"`,图标资源见上方「应用图标」一节

### Windows

1. `flutter build windows --release`,产物在 `build/windows/x64/runner/Release/`
2. 分发可用 MSIX(`msix` pub 包)或 Inno Setup 打包安装器;图标替换 `windows/runner/resources/app_icon.ico`
3. 回归:文件选择器选背景图 / 导入备份、中文路径下的数据目录

### 通用

- 升级版本号后,Hive 适配器字段序号只允许追加,不得重排或复用
- 数据库永远只存相对路径;新功能引入文件时走 `PathUtils`,禁止手工拼接绝对路径

## 已知设计取舍

- Flutter 3.0 无 `BuildContext.mounted`(3.4 引入),代码用 `contextIsAlive` 守卫 + 文件级 `use_build_context_synchronously` 忽略,原因见 `lib/shared/widgets/common.dart` 注释
- `go_router` 4.5 早于 `routerConfig`,`MaterialApp.router` 需分别传 provider / parser / delegate 三参,见 `lib/moepick_app.dart`
- 对话框输入框的 `TextEditingController` 由对话框 `State` 持有并在其 `dispose` 中释放——不要改回函数内创建 + `whenComplete` 释放的写法,那会在退场动画期间释放仍被监听的 controller 并导致连锁崩溃,回归测试见 `test/shared/text_prompt_test.dart`
