class_name PlatformAdapter
extends RefCounted
# UI-001 实现：桌面平台差异抽象（macOS Apple Silicon 为 v0.1 主验收，Windows 11 尽早可行性验证）。
# Godot native 窗口属性不能仅靠 headless 自动证实；须用独立可见 GUI 技术探针并留人工验收证据（AGENTS.md §4）。
# 本票仅骨架；骨架阶段暂继承 RefCounted，UI-001 按实现需要再定基类。
