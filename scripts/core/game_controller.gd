class_name GameController
extends Node
# CORE-001 主场景入口骨架：_ready 仅创建 GameState 并打印初始化行。
# 业务编排（FSM 驱动、经济提交、存档调度）分属 FSM-001 / ECO-001 / SAVE-001，本票不实现。

func _ready() -> void:
	var state := GameState.new()
	print("CORE001 GameController ready: wallet_gold=%d basket=%d basket_capacity=%d" % [
		state.wallet_gold, state.basket.size(), state.basket_capacity])
