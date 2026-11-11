extends SceneTree
# CORE-001 headless 冒烟测试（工单最小验收「Godot 无语法/导入错误」）。
# 运行：Godot --headless --path <repo> -s res://tests/unit/test_core001_smoke.gd
# 全部通过打印 CORE001 SMOKE PASS 并 quit(0)；任一失败打印 CORE001 SMOKE FAIL: <step> 并 quit(1)。

const SCRIPTS := [
	"res://scripts/core/game_controller.gd",
	"res://scripts/core/game_state.gd",
	"res://scripts/core/fishing_system.gd",
	"res://scripts/io/config_loader.gd",
	"res://scripts/io/save_service.gd",
	"res://scripts/io/event_log.gd",
	"res://scripts/platform/platform_adapter.gd",
	"res://scripts/platform/desktop_window.gd",
	"res://scripts/presentation/cat_presenter.gd",
]

func _initialize() -> void:
	for path in SCRIPTS:
		if load(path) == null:
			_fail("load " + path)
			return
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail("load res://scenes/main.tscn")
		return
	var main := packed.instantiate()
	if not (main is Node2D) or String(main.name) != "Main":
		main.free()
		_fail("main scene root must be Node2D named Main")
		return
	root.add_child(main)
	var state := GameState.new()
	if state.wallet_gold != 0:
		_fail("GameState.wallet_gold default must be 0")
		return
	if not state.basket.is_empty():
		_fail("GameState.basket default must be empty")
		return
	if state.basket_capacity != 10:
		_fail("GameState.basket_capacity default must be 10 (candidate)")
		return
	if state.save_version != 1:
		_fail("GameState.save_version default must be 1")
		return
	print("CORE001 SMOKE PASS")
	quit(0)

func _fail(step: String) -> void:
	print("CORE001 SMOKE FAIL: " + step)
	quit(1)
