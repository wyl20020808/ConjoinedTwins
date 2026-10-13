# Mac 归航 Demo 测试说明

新版文件：`builds/macos/ConjoinedTwins-macOS-universal.zip`，版本 0.3.0，内含 `共生连线 · 归航 Demo.app`。Universal 2 支持 Intel x86_64 与 Apple Silicon arm64；preset 最低版本为 Intel macOS 11、Apple Silicon macOS 13。无需安装 Godot，没有在线 API。本轮大小 61,188,068 字节，SHA256 为 `899df5e702966f1d171be3960b2be2b97386af86291b7d30137d62532e5cca5b`；证据见 [本轮交付报告](LOCAL_DELIVERY_REPORT.md)。

将 ZIP 复制到 Mac，用 Finder 解压，再打开应用。开始页选择简单、普通或困难，默认普通；回车、空格或按钮开始。01 使用 WASD 四向移动、空格跳跃；02 使用方向键四向移动、回车跳跃。无限自动推进，双方独立前后调节 ±3.5 米、保持 11 米地面连接，无 AI 接管、模式切换或低姿态动作。Esc 暂停/继续，R 共同重试；启动、恢复和重试后松开旧按键再按。低栏、地刺、低位飞行物可跳或绕，高货箱与高大危险须绕行。黄色预警、红色危险、绿色安全均有文字提示。

此包仅使用 Godot Built-in ad-hoc 签名，未进行 Developer ID 签名或 Apple 公证。首次被 Gatekeeper 阻止时，先在系统设置“隐私与安全性”找到本应用的提示，选择“仍要打开”，按系统确认完成。不要关闭系统 Gatekeeper。

需要诊断时，下列命令仅查看此应用，路径按实际解压位置调整：

```bash
codesign --verify --deep --strict --verbose=2 "$HOME/Downloads/共生连线 · 归航 Demo.app"
spctl --assess --type execute --verbose "$HOME/Downloads/共生连线 · 归航 Demo.app"
```

未公证的本地测试包可能被 spctl 拒绝，这不等同于静态结构验证失败。若 Finder 提示损坏，先核对 ZIP SHA256 与本轮报告一致，再保留错误信息交决策者排查；不要全局移除隔离属性或关闭系统安全机制。

Windows 已完成包结构、双架构、Unix 执行权限、实际签名代码页与资源封印检查，以及实际 ZIP 中 PCK 的隔离 headless 加载；这些不等同于 Mac 二进制、Apple 原生 codesign 验证或图形兼容性通过。Mac 实机、中文显示、键盘多键并按、帧率、双人手感和晕动体验仍待用户试玩。请记录机型、macOS、所选难度、累计距离、失败原因与画面，并检查两人同时移动/跳跃、暂停恢复、快速重试及固定镜头舒适性；不要把脚本输入当作实体键盘测试。
