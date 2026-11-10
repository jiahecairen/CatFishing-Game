# SPIKE-001 — macOS 透明桌面窗口技术探针

**优先级 P0 / 必须先验收。** 目标是用最小 Godot 4 工程在用户 Mac 上**实际**验证桌面交互能力；不是在 ChatGPT 的 Linux 环境假装成功。

## 1. 前置只读调查

- `pwd; ls -la; git status --short`（无 Git 仓库时先记录，不强制 init）。
- `command -v godot || command -v godot4 || true`。
- 常见 macOS App 位置也可按实际位置检查：`/Applications/Godot.app/Contents/MacOS/Godot --version`（仅在路径存在时运行）。
- 识别 Godot 4 具体小版本、渲染器、窗口系统，验证 headless 命令能用。
- 读文档后提交计划；Plan Mode 不写文件。

## 2. 技术研究与候选 Godot API

Godot 4 官方 GUI Overlay 文档说明可使用窗口透明和 `Window.mouse_passthrough` / `mouse_passthrough_polygon`，但必须在**窗口真实运行而非嵌入 Godot 编辑器**时验收。穿透多边形与完全穿透属性有优先级关系；透明视觉 != 鼠标穿透。

优先验证：

- 项目/Window 透明背景、borderless、合适的独立窗口渲染模式。
- 允许背景桌面/App 正常接收透明区鼠标点击，船/猫命中区可交互。
- 船/猫拖动与点击阈值，位置记忆，屏幕边缘不会把窗口拖至不可恢复的位置。
- 对应 macOS Retina 不同缩放；窗口被全屏 App 覆盖时尊重系统行为。
- `Engine.max_fps = 30` 或准确的等价设置；逻辑计时不依赖 `_process` 帧数。

**官方参考**：
- https://docs.godotengine.org/en/stable/tutorials/ui/creating_applications.html
- https://docs.godotengine.org/en/stable/classes/class_window.html

以上是待验证的技术候选，并非已通过的配置。

## 3. 最小实验用例

1. 新建隔离的 `tests/spike/overlay` 或按现有 repo 结构放置独立测试场景，不覆盖现有入口。
2. 无边框透明窗口，至少显示一块不透明“船”占位像素及一块完全透明区域。
3. 交互区域：点击能触发临时状态提示；透明区点击落在下方 Finder/浏览器而不会被空窗口拦截。
4. 在主屏/外接显示器拖动，重启后保存位置，屏幕断开后安全回退。
5. 记录 CPU/内存/FPS，观察 UI 是否抢焦点、是否拖动卡顿。
6. 使用 Godot headless 验证脚本/场景可加载；**不能**把这一步当成透明穿透的 GUI 通过证据。

## 4. 结果和风险单

输出：具体 Godot 版本、启动命令、平台、实际设置、窗口截图/短视频（只取游戏窗口，不泄露桌面私密内容）、成功/失败矩阵、必要 fallback 的用户可选方案。碰到 macOS API 限制不能自行牺牲透明/穿透功能，必须将替代方案提交用户批准。

## 5. 放行条件

- 透明桌面叠加、可交互命中区与透明区穿透均由真实 GUI 证明。
- 拖动/点击无严重冲突，窗口位置持久化正常。
- 30 FPS 设置与逻辑时钟解耦。
- 所有有条件或未验证行为在报告中明确，不得写“全部完成”。
