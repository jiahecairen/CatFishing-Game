extends CanvasLayer
# UI-001：视图容器（plan §2）——仅承载 HUD/鱼篓面板/猫船节点并转发信号。
# 不拥有金币、鱼篓或交易账本（唯一权威是 GameState，经 FishingSession 只读发布）。
# headless 短路（plan §4.9 / R-U4）：CORE smoke 在 headless 实例化本场景时，
# _ready 不做任何窗口/写盘副作用。

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# 视图节点在场景中静态声明；具体装配与信号接线由 GameController._ready 完成。
	# 本容器刻意零逻辑：任何金币/鱼篓数值都不允许在此计算或缓存。
