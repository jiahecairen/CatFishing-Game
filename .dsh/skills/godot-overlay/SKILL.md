---
name: godot-overlay
description: Validate Godot 4 macOS transparent desktop overlay windows, click-through, drag, Retina and visible 30 FPS using a GUI technical spike.
---

# Godot Desktop Overlay — 项目 Skill

**何时使用**：透明无边框、macOS 原生窗口、鼠标穿透、拖动定位、Retina、固定 30 FPS 或相关 Bug 工单。

1. 先读 `AGENTS.md`、`docs/SDD_v0.1.md`、`docs/TECH_SPIKE.md`、`tasks/TASKS.md`。核实当前 Godot 4 版本和 Git 状态。
2. Plan Mode 只读审查，待用户批准 SPIKE-001 后再在隔离路径创建探针，不改已有入口。
3. 官方 Godot 4 文档的 `Window.mouse_passthrough` 与 `Window.mouse_passthrough_polygon` 有不同语义。务必区分透明视觉和输入穿透；**不要**把整个可交互区域也设为全窗口穿透。
4. Godot 编辑器嵌入式运行可能掩盖真实窗口特性，必须 Mac 原生窗口 GUI 验证；headless 只能验证导入/脚本语法。
5. 拖动要设阈值、坐标保存、边缘安全回退；透明区必须允许下方应用接收点击。
6. **可见时 30 FPS** 是 SDD-175 已确定硬约束；逻辑/等待时间不依赖帧数。
7. 遇到平台限制，记录可复核的证据和可选替代方案，未经用户批准不得降级需求。

参考：https://docs.godotengine.org/en/stable/tutorials/ui/creating_applications.html
