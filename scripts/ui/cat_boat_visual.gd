class_name CatBoatVisual
extends Control
# Temporary vector placeholder for the v0.1 cat and fishing boat. No production art assets.

signal pointer_event(event: InputEvent)

const INK := Color("243447")
const WOOD := Color("c87842")
const WOOD_LIGHT := Color("e6a567")
const WATER := Color("5db8c4")
const CREAM := Color("fff0ce")
const ORANGE := Color("e9864f")
const SIZE := Vector2(144, 76)


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	queue_redraw()


func _draw() -> void:
	# A few short wave strokes anchor the boat without adding an opaque backdrop.
	draw_line(Vector2(4, 65), Vector2(28, 65), WATER, 2.0, true)
	draw_line(Vector2(112, 69), Vector2(139, 69), WATER, 2.0, true)
	draw_line(Vector2(18, 72), Vector2(42, 72), Color(WATER, 0.7), 1.0, true)

	# Hull.
	var hull := PackedVector2Array([
		Vector2(9, 42), Vector2(135, 42), Vector2(121, 65),
		Vector2(28, 65), Vector2(16, 56),
	])
	draw_colored_polygon(hull, WOOD)
	draw_polyline(PackedVector2Array([
		Vector2(9, 42), Vector2(135, 42), Vector2(121, 65),
		Vector2(28, 65), Vector2(16, 56), Vector2(9, 42),
	]), INK, 2.0, true)
	draw_line(Vector2(20, 51), Vector2(128, 51), WOOD_LIGHT, 2.0, true)
	draw_line(Vector2(32, 58), Vector2(117, 58), Color(INK, 0.35), 1.0, true)

	# Seated orange cat: body, head, ears, paws, eyes, and whiskers.
	_draw_ellipse(Vector2(75, 42), Vector2(20, 12), Color(INK, 0.22))
	draw_colored_polygon(PackedVector2Array([
		Vector2(60, 43), Vector2(63, 30), Vector2(70, 25),
		Vector2(81, 26), Vector2(88, 35), Vector2(87, 45),
	]), ORANGE)
	draw_circle(Vector2(75, 24), 12.0, ORANGE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(65, 17), Vector2(65, 5), Vector2(73, 13),
	]), ORANGE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(77, 13), Vector2(86, 6), Vector2(85, 19),
	]), ORANGE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(67, 16), Vector2(68, 10), Vector2(72, 15),
	]), Color("f3b0a0"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(79, 15), Vector2(84, 10), Vector2(83, 17),
	]), Color("f3b0a0"))
	_draw_ellipse(Vector2(75, 28), Vector2(7, 4), CREAM)
	draw_circle(Vector2(72, 27), 1.2, INK)
	draw_circle(Vector2(78, 27), 1.2, INK)
	draw_circle(Vector2(75, 30), 1.2, Color("a94f50"))
	draw_line(Vector2(75, 31), Vector2(75, 34), INK, 1.0, true)
	draw_line(Vector2(71, 32), Vector2(61, 30), CREAM, 1.0, true)
	draw_line(Vector2(71, 34), Vector2(61, 36), CREAM, 1.0, true)
	draw_line(Vector2(79, 32), Vector2(89, 30), CREAM, 1.0, true)
	draw_line(Vector2(79, 34), Vector2(89, 36), CREAM, 1.0, true)
	_draw_ellipse(Vector2(69, 43), Vector2(5, 3), CREAM)
	_draw_ellipse(Vector2(82, 43), Vector2(5, 3), CREAM)
	draw_line(Vector2(88, 43), Vector2(96, 47), ORANGE, 3.0, true)
	draw_arc(Vector2(97, 43), 8.0, 0.15, 2.4, 12, ORANGE, 3.0, true)

	# Fishing rod, line, float, and a small fish on the line.
	draw_line(Vector2(83, 13), Vector2(126, 3), WOOD_LIGHT, 2.0, true)
	draw_line(Vector2(126, 3), Vector2(134, 23), Color("e6f4ef"), 1.0, true)
	draw_circle(Vector2(134, 25), 2.0, Color("ef6d64"))
	draw_line(Vector2(126, 57), Vector2(134, 53), Color("8bd3d1"), 1.5, true)
	draw_line(Vector2(134, 53), Vector2(139, 56), Color("8bd3d1"), 1.5, true)
	draw_circle(Vector2(137, 54), 1.0, INK)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		pointer_event.emit(event)
		accept_event()


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 24:
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
