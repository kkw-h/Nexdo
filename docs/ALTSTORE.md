# 使用 AltStore 安装 Nexdo

本指南介绍如何在 macOS 上构建 `.ipa` 包并通过 AltStore/AltServer 安装到 iPhone 或 iPad。

## 先决条件

- macOS 13+，已安装 Xcode(Command Line Tools) 与 Flutter SDK。
- iPhone/iPad 已信任 AltStore（参见 <https://altstore.io> 官方步骤）。
- `altserver` 运行在同一台 Mac，并且设备与 Mac 通过数据线或同一 Wi-Fi 连接。

## 1. 构建 AltStore 版本 `.ipa`

项目根目录已经提供脚本 `scripts/build_ipa_nosign.sh`，它会：

1. 运行 `flutter pub get`
2. 执行 `flutter build ios --release --no-codesign`
3. 将 `build/ios/iphoneos/Runner.app` 包装成 `Payload/Runner.app`
4. 压缩生成 `build/altstore/Nexdo-AltStore.ipa`

命令：

```bash
./scripts/build_ipa_nosign.sh
```

执行完成后，可在 `build/ios/ipa/nexdo-<version>-nosign.ipa` 找到未签名的安装包。

也可以手动指定版本号：

```bash
./scripts/build_ipa_nosign.sh 1.0.0
```

> AltStore 会在安装时使用你的 Apple ID 重新签名，因此此处无需配置任何证书。

## 2. 使用 AltStore 安装

1. 确保 AltServer 正在 Mac 菜单栏运行，并且你的设备出现在 AltServer 的「Install AltStore」菜单中。
2. 打开设备上的 AltStore，切换到「我的应用(My Apps)」，点击左上角 `+` 按钮。
3. 选择刚才导出的 `Nexdo-AltStore.ipa`，AltStore 会提示输入 Apple ID，随后自动签名并安装。
4. 安装成功后，首次打开需在设备的「设置 > 通用 > VPN 与设备管理」里信任该签名。

## 3. （可选）发布 AltStore Source

如果想要让他人通过 AltStore 的「Sources」自动获取更新，可以：

1. 将 `.ipa` 上传到可公开访问的链接（例如 GitHub Releases）。
2. 复制 `altstore/source.json`，修改其中的 `downloadURL`、`localizedDescription`、`version` 等字段，并将该 JSON 文件也托管在公开地址。
3. 在 AltStore 中添加该 Source URL，即可看到「Nexdo」应用并一键安装/更新。

## 常见问题

- **构建异常**：确认已经在 macOS 上运行 `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` 并接受许可。
- **AltStore 安装失败**：通常是 Apple ID/密码错误或设备与 Mac 的网络不在同一网段。可在 AltStore 中查看失败日志。
- **签名 7 天过期**：AltStore 会在后台自动刷新签名，保持设备与 AltServer 处于同一网络并定期开启 AltStore。

如需自动化 GitHub Release/Source 发布，可扩展现有 CI，在构建阶段上传 `.ipa` 至 Release 并更新 `source.json` 中的下载链接。
