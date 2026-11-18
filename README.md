# BabyCabin 鸿蒙 APP

基于 ArkTS / ArkUI 的原生客户端。源码位于 [entry/src](entry/src/)，接入电脑端 Python 网关进行局域网 TLS 配对、实时画面、状态与控制预演，不在手机上运行识别模型。

1. 在 DevEco Studio 打开本仓库，安装与 build-profile.json5 相符的 HarmonyOS SDK。
2. 在本机配置自己的调试签名，构建 entry 模块并安装至已授权的测试设备。可用项目的 assembleHap 任务。
3. 启动[电脑端网关](https://github.com/13261688309/babycabin-desktop-web)，在电脑配对页获取本次配对码，手机连同一局域网，按界面配对。

[历史未签名 HAP](artifacts/preview-freshness-unsigned.hap) 是独立的预览修复构建快照，不代表当前源码已重新构建，也不能直接作为签名安装包。仓库不含本机证书、签名密钥、账号配置和设备记录。

仅用于无人桌面演示；手机下发目标或显示主控回执，不等于实物动作和断电保护验收。

[项目及结题材料](https://github.com/13261688309/babycabin-project) · [电脑端网页](https://github.com/13261688309/babycabin-desktop-web)
