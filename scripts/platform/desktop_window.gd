class_name DesktopWindow
extends RefCounted
# UI-001 实现：透明桌面悬浮窗口、鼠标穿透、拖动阈值、全屏/隐藏时避免干扰桌面工作。
# 拖动期临时 60 FPS 例外属 UI-001 后续实现，本票不声称已实现（主工程保持 run/max_fps=30）。
# 本票仅骨架，不含任何窗口属性设置。
