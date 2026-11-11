class_name CatPresenter
extends RefCounted
# Creates the procedural placeholder and reports its interactive rectangle. It owns no game state.

const CatVisualScript := preload("res://scripts/ui/cat_boat_visual.gd")
const CAT_POSITION := Vector2(38, 76)


func create_visual(parent: Control) -> CatBoatVisual:
	var visual: CatBoatVisual = CatVisualScript.new()
	visual.name = "CatBoat"
	visual.position = CAT_POSITION
	parent.add_child(visual)
	return visual


func interaction_rect(visual: Control) -> Rect2:
	return visual.get_global_rect() if is_instance_valid(visual) else Rect2()
