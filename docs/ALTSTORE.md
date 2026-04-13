# 使用 AltStore 安装 Nexdo

本指南介绍如何在 macOS 上构建 `.ipa` 包并通过 AltStore/AltServer 安装到 iPhone 或 iPad。

## 先决条件

- macOS 13+，已安装 Xcode(Command Line Tools) 与 Flutter SDK。
- iPhone/iPad 已信任 AltStore（参见 <https://altstore.io> 官方步骤）。
- `altserver` 运行在同一台 Mac，并且设备与 Mac 通过数据线或同一 Wi-Fi 连接。

## 1. 构建 AltStore 版本 `.ipa`

针对 AltStore 场景，推荐使用脚本 `scripts/build_altstore_ipa.sh`：

```bash
# 默认会根据 pubspec.yaml 的 version 自动读取版本，并假设 Git Tag 为 v<version>
./scripts/build_altstore_ipa.sh

# 如果 Release 使用其他标签，可显式指定
./scripts/build_altstore_ipa.sh --tag release-2026-04-13
```

脚本会执行以下动作：

1. 执行 `flutter pub get` 与 `flutter build ios --release --no-codesign`。
2. 将 `build/ios/iphoneos/Runner.app` 打包为 `build/altstore/Nexdo-AltStore-<version>.ipa`。
3. 根据构建结果更新 `altstore/source.json`：写入版本号、构建日期、文件大小，以及 GitHub Release 下载 URL（默认 `https://github.com/kkw-h/Nexdo/releases/download/v<version>/...`）。

脚本结束后会打印：

- IPA 的本地路径（供 AltStore 手动加载或上传 Release）。
- 预期的 GitHub Release 标签与下载 URL。
- `source.json` 的托管地址（默认 `https://raw.githubusercontent.com/kkw-h/Nexdo/main/altstore/source.json`，可通过 `ALTSTORE_SOURCE_URL` 环境变量覆盖）。

> 若仅需一个通用的无签名 IPA，可继续使用 `scripts/build_ipa_nosign.sh`。

## 2. 使用 AltStore 安装

1. 确保 AltServer 正在 Mac 菜单栏运行，并且你的设备出现在 AltServer 的「Install AltStore」菜单中。
2. 打开设备上的 AltStore，切换到「我的应用(My Apps)」，点击左上角 `+` 按钮。
3. 选择刚才导出的 `Nexdo-AltStore.ipa`，AltStore 会提示输入 Apple ID，随后自动签名并安装。
4. 安装成功后，首次打开需在设备的「设置 > 通用 > VPN 与设备管理」里信任该签名。

## 3. （可选）发布 AltStore Source

如果想要让他人通过 AltStore 的「Sources」自动获取更新，现在可以直接复用仓库内的配置：

1. 在 GitHub 上创建/更新 Release（标签需与 `build_altstore_ipa.sh` 输出一致），上传 `build/altstore/Nexdo-AltStore-<version>.ipa`。
2. 将 `altstore/source.json` 托管在公开地址（推荐使用 GitHub Raw：`https://raw.githubusercontent.com/kkw-h/Nexdo/main/altstore/source.json`，或上传到自己的静态站点）。
3. AltStore 中打开「Settings -> Sources -> +」，填入上面的 Source URL，即可自动展示 Nexdo，并根据 GitHub Release 下载最新 IPA。

`source.json` 中的 `downloadURL` 默认指向 `https://github.com/kkw-h/Nexdo/releases/download/<tag>/Nexdo-AltStore-<version>.ipa`。如需将文件放在其他 CDN/对象存储，可手动修改该字段或在执行脚本前设置 `ALTSTORE_DOWNLOAD_BASE` 环境变量。

## 常见问题

- **构建异常**：确认已经在 macOS 上运行 `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` 并接受许可。
- **AltStore 安装失败**：通常是 Apple ID/密码错误或设备与 Mac 的网络不在同一网段。可在 AltStore 中查看失败日志。
- **签名 7 天过期**：AltStore 会在后台自动刷新签名，保持设备与 AltServer 处于同一网络并定期开启 AltStore。

如需自动化 GitHub Release/Source 发布，可扩展现有 CI，在构建阶段上传 `.ipa` 至 Release 并更新 `source.json` 中的下载链接。
