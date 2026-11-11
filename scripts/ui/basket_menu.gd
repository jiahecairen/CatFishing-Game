class_name BasketMenu
extends PanelContainer
# UI-001：鱼篓菜单（plan §2/§4.2/§4.3）——「出售所选」「出售全部」两动作 + 关闭。
# 每行显示鱼种名与「出售时价格快照」（sale_price_at_catch，ECO-001 §5 计价权威），
# 金币/鱼清单权威只在 GameState（经 FishingSession 命令），本面板不记账。
# 提交中禁用按钮（意图层去重的 UI 侧，R-U8）；售鱼 sale ID 由会话生成，面板不生成 ID。

signal sell_requested(instance_ids: Array)
signal sell_all_requested()
signal closed()

var _rows: VBoxContainer
var _title: Label
var _selected_button: Button
var _sell_all_button: Button
var _close_button: Button
var _submitting := false
var _item_count := 0
var _last_stamp := ""


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(208, 104)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("eaf7f5")
	panel_style.border_color = Color("4b8290")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", panel_style)
	var root := VBoxContainer.new()
	root.name = "Rows"
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_theme_constant_override("separation", 2)
	add_child(root)
	_title = Label.new()
	_title.name = "Title"
	_title.text = "鱼篓 · 0/10"
	_title.add_theme_font_size_override("font_size", 11)
	_title.add_theme_color_override("font_color", Color("243447"))
	root.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.name = "FishScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(192, 58)
	root.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "FishRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 0)
	scroll.add_child(_rows)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 3)
	root.add_child(buttons)
	_selected_button = _make_button(buttons, "SellSelected", "出售所选", _on_selected_pressed)
	_sell_all_button = _make_button(buttons, "SellAll", "出售全部", _on_sell_all_pressed)
	_close_button = _make_button(buttons, "Close", "关闭", _on_close_pressed)


## 只读重建行列表。names_by_id: species_id -> 中文名（会话提供，仅展示）。
func update_items(basket: Array, names_by_id: Dictionary, submitting: bool) -> void:
	_submitting = submitting
	_item_count = basket.size()
	_title.text = "鱼篓 · %d/10" % _item_count
	var stamp := JSON.stringify([basket, names_by_id])
	if stamp != _last_stamp:
		_last_stamp = stamp
		var selected_ids := selected_instance_ids()
		for child in _rows.get_children():
			_rows.remove_child(child)
			child.queue_free()
		for element in basket:
			if not (element is Dictionary):
				continue
			var fish: Dictionary = element
			var instance_id := String(fish.get("instance_id", ""))
			var checkbox := CheckBox.new()
			checkbox.name = "Fish_%s" % instance_id
			var species_id := String(fish.get("species_id", ""))
			var display := String(names_by_id.get(species_id, species_id))
			checkbox.text = "%s  ·  %d 金币" % [display, int(fish.get("sale_price_at_catch", 0))]
			checkbox.add_theme_font_size_override("font_size", 10)
			checkbox.add_theme_color_override("font_color", Color("243447"))
			checkbox.button_pressed = selected_ids.has(instance_id)
			_rows.add_child(checkbox)
	_refresh_buttons()


func selected_instance_ids() -> Array:
	var ids: Array = []
	for child in _rows.get_children():
		if child is CheckBox and (child as CheckBox).button_pressed:
			ids.append(String(child.name).substr("Fish_".length()))
	return ids


func set_submitting(submitting: bool) -> void:
	_submitting = submitting
	_refresh_buttons()


func _refresh_buttons() -> void:
	_selected_button.disabled = _submitting or selected_instance_ids().is_empty()
	_sell_all_button.disabled = _submitting or _item_count == 0
	_close_button.disabled = _submitting


func _make_button(parent: Node, node_name: String, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_color_override("font_color", Color("243447"))
	button.add_theme_color_override("font_hover_color", Color("142434"))
	button.add_theme_color_override("font_pressed_color", Color("142434"))
	button.add_theme_color_override("font_disabled_color", Color("68737c"))
	button.custom_minimum_size = Vector2(0, 22)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _on_selected_pressed() -> void:
	sell_requested.emit(selected_instance_ids())


func _on_sell_all_pressed() -> void:
	sell_all_requested.emit()


func _on_close_pressed() -> void:
	closed.emit()
