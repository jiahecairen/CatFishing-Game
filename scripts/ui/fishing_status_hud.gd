class_name FishingStatusHUD
extends Control
# UI-001：紧凑钓鱼状态 HUD（plan §2/§4.2/§4.4）。金币、鱼篓 n/capacity、FSM 状态名一律
# 只读自 FishingSession.status_view()（权威 = GameState），HUD 不记账、不计时。
# 保存失败可见态（V01-S02/T-UI-01）：常驻、非模态、无系统通知横幅「存档失败：经济已暂停」+
# 重试入口；输入未开放（启动 fail closed）时显示未提交原因，绝不显示未确认收入。
# 更新只由 GameController 在持久化提交后调用 update_status()（UI 层幂等：同 view 重复
# 调用零视觉差异，R-U8 依赖此性质）。

signal retry_requested()
signal hide_requested()

var _gold_label: Label
var _basket_label: Label
var _state_label: Label
var _banner: Label
var _retry_button: Button
var _hide_button: Button
var _last_text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD 只读展示，不拦截桌面点击
	_add_status_plate()
	_gold_label = _make_label(Vector2(8, 2), "金币: 0")
	_basket_label = _make_label(Vector2(8, 16), "鱼篓: 0/10")
	_state_label = _make_label(Vector2(8, 30), "状态: -")
	_banner = Label.new()
	_banner.name = "SaveErrorBanner"
	_banner.position = Vector2(8, 46)
	_banner.size = Vector2(204, 14)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	_banner.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.06, 0.95))
	_banner.add_theme_constant_override("outline_size", 2)
	_banner.add_theme_font_size_override("font_size", 10)
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_retry_button = Button.new()
	_retry_button.name = "SaveRetryButton"
	_retry_button.text = "重试保存"
	_retry_button.position = Vector2(150, 2)
	_retry_button.size = Vector2(62, 18)
	_retry_button.visible = false
	_retry_button.pressed.connect(_on_retry_pressed)
	add_child(_retry_button)
	_hide_button = Button.new()
	_hide_button.name = "HideOverlayButton"
	_hide_button.text = "隐藏"
	_hide_button.position = Vector2(164, 26)
	_hide_button.size = Vector2(38, 18)
	_hide_button.add_theme_font_size_override("font_size", 9)
	_hide_button.add_theme_color_override("font_color", Color("243447"))
	_hide_button.pressed.connect(func(): hide_requested.emit())
	add_child(_hide_button)


func _add_status_plate() -> void:
	var plate := Panel.new()
	plate.name = "StatusPlate"
	plate.position = Vector2(2, 0)
	plate.size = Vector2(208, 48)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.085, 0.12, 0.9)
	style.border_color = Color(0.34, 0.58, 0.64, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	plate.add_theme_stylebox_override("panel", style)
	add_child(plate)
	move_child(plate, 0)


## 只读渲染（不产生任何业务副作用）。
func update_status(view: Dictionary) -> void:
	var gold := int(view.get("gold", 0))
	var basket_count := int(view.get("basket_count", 0))
	var capacity := int(view.get("basket_capacity", 10))
	var state_name := String(view.get("state", "-"))
	var save_error := bool(view.get("save_error", false))
	var input_open := bool(view.get("input_open", false))
	_gold_label.text = "金币: %d" % gold
	_basket_label.text = "鱼篓: %d/%d%s" % [basket_count, capacity, "（满篓停抛）" if bool(view.get("basket_full", false)) else ""]
	_state_label.text = "状态: %s" % state_name
	if save_error:
		_banner.text = "存档失败：经济已暂停（可重试）"
		_banner.visible = true
		_retry_button.visible = true
	elif not input_open:
		_banner.text = "启动失败：%s（输入未开放）" % String(view.get("boot_code", "UNKNOWN"))
		_banner.visible = true
		_retry_button.visible = true
	else:
		_banner.visible = false
		_retry_button.visible = false
	var stamp := "%s|%s|%s|%s" % [_gold_label.text, _basket_label.text, _state_label.text, _banner.text]
	if stamp == _last_text:
		return  # 同 view 幂等
	_last_text = stamp


func _make_label(at: Vector2, text: String) -> Label:
	var label := Label.new()
	label.position = at
	label.size = Vector2(140, 14)
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.96))
	label.add_theme_constant_override("outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _on_retry_pressed() -> void:
	retry_requested.emit()


func hide_button_rect() -> Rect2:
	if not is_instance_valid(_hide_button):
		return Rect2()
	return _hide_button.get_global_rect()
