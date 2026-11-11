class_name UIRoot
extends CanvasLayer
# View-only runtime container. FishingSession/GameState remain the only source of game values.

signal boat_pointer_event(event: InputEvent)
signal sell_requested(instance_ids: Array)
signal sell_all_requested
signal retry_requested
signal hide_requested
signal interaction_regions_changed

const HudScript := preload("res://scripts/ui/fishing_status_hud.gd")
const BasketScript := preload("res://scripts/ui/basket_menu.gd")
const PresenterScript := preload("res://scripts/presentation/cat_presenter.gd")

var _root: Control
var _hud: FishingStatusHUD
var _basket_menu: BasketMenu
var _boat: CatBoatVisual
var _session: FishingSession
var _initialized := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return


func initialize(session: FishingSession) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "code": "HEADLESS"}
	if session == null or _initialized:
		return {"ok": false, "code": "BAD_INJECTION" if session == null else "ALREADY_INITIALIZED"}
	_session = session
	_root = Control.new()
	_root.name = "OverlayContent"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var presenter: CatPresenter = PresenterScript.new()
	_boat = presenter.create_visual(_root)
	_boat.pointer_event.connect(_on_boat_pointer_event)
	_hud = HudScript.new()
	_hud.name = "FishingStatusHUD"
	_hud.position = Vector2(6, 4)
	_hud.size = Vector2(208, 48)
	_root.add_child(_hud)
	_basket_menu = BasketScript.new()
	_basket_menu.name = "BasketMenu"
	_basket_menu.position = Vector2(6, 52)
	_basket_menu.size = Vector2(208, 104)
	_root.add_child(_basket_menu)
	_basket_menu.sell_requested.connect(_on_sell_requested)
	_basket_menu.sell_all_requested.connect(_on_sell_all_requested)
	_basket_menu.closed.connect(close_basket)
	_hud.retry_requested.connect(func(): retry_requested.emit())
	_hud.hide_requested.connect(func(): hide_requested.emit())
	_initialized = true
	refresh()
	interaction_regions_changed.emit()
	return {"ok": true, "code": ""}


func refresh() -> void:
	if not _initialized or _session == null:
		return
	var view: Dictionary = _session.status_view()
	_hud.update_status(view)
	_basket_menu.update_items(view.get("basket", []), _session.species_names(), false)


func toggle_basket() -> void:
	if not _initialized:
		return
	_basket_menu.visible = not _basket_menu.visible
	refresh()
	interaction_regions_changed.emit()


func close_basket() -> void:
	if not _initialized or not _basket_menu.visible:
		return
	_basket_menu.visible = false
	interaction_regions_changed.emit()


func interaction_rects() -> Array:
	var rects: Array = []
	if is_instance_valid(_boat):
		rects.append(_boat.get_global_rect())
	if is_instance_valid(_hud):
		rects.append(_hud.hide_button_rect())
	if _initialized and _basket_menu.visible:
		rects.append(_basket_menu.get_global_rect())
	return rects


func set_submitting(value: bool) -> void:
	if _initialized:
		_basket_menu.set_submitting(value)


func _on_boat_pointer_event(event: InputEvent) -> void:
	boat_pointer_event.emit(event)


func _on_sell_requested(instance_ids: Array) -> void:
	_basket_menu.set_submitting(true)
	sell_requested.emit(instance_ids.duplicate(true))


func _on_sell_all_requested() -> void:
	_basket_menu.set_submitting(true)
	sell_all_requested.emit()
