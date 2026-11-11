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


func _ready() -> void:
	visible = false
	var root := VBoxContainer.new()
	root.name = "Rows"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_title = Label.new()
	_title.name = "Title"
	_title.text = "鱼篓"
	_title.add_theme_font_size_override("font_size", 10)
	root.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.name = "FishRows"
	root.add_child(_rows)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	root.add_child(buttons)
	_selected_button = _make_button(buttons, "SellSelected", "出售所选", _on_selected_pressed)
	_sell_all_button = _make_button(buttons, "SellAll", "出售全部", _on_sell_all_pressed)
	_close_button = _make_button(buttons, "Close", "关闭", _on_close_pressed)


## 只读重建行列表。names_by_id: species_id -> 中文名（会话提供，仅展示）。
func update_items(basket: Array, names_by_id: Dictionary, submitting: bool) -> void:
	_submitting = submitting
	for child in _rows.get_children():
		child.queue_free()
		_rows.remove_child(child)
	for element in basket:
		var fish: Dictionary = element
		var checkbox := CheckBox.new()
		checkbox.name = "Fish_%s" % String(fish.get("instance_id", ""))
		var species_id := String(fish.get("species_id", ""))
		var display := String(names_by_id.get(species_id, species_id))
		checkbox.text = "%s ×%d" % [display, int(fish.get("sale_price_at_catch", 0))]
		checkbox.add_theme_font_size_override("font_size", 10)
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
	var disabled := _submitting
	_selected_button.disabled = disabled
	_sell_all_button.disabled = disabled
	_close_button.disabled = disabled


func _make_button(parent: Node, node_name: String, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.add_theme_font_size_override("font_size", 9)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _on_selected_pressed() -> void:
	sell_requested.emit(selected_instance_ids())


func _on_sell_all_pressed() -> void:
	sell_all_requested.emit()


func _on_close_pressed() -> void:
	closed.emit()
