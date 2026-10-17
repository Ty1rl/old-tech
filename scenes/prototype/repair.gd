extends Control

const Tuning = preload("res://scenes/prototype/tuning.gd")
const BOARD := Vector2(560, 240)
const CORRIDOR := 25.0
const CONTACT := 21.0
const ROUTES := [
	[Vector2(55, 120), Vector2(180, 65), Vector2(280, 175), Vector2(405, 65), Vector2(505, 120)],
	[Vector2(55, 120), Vector2(165, 175), Vector2(275, 65), Vector2(395, 175), Vector2(505, 120)],
	[Vector2(55, 120), Vector2(180, 120), Vector2(280, 60), Vector2(400, 120), Vector2(505, 120)],
	[Vector2(55, 120), Vector2(160, 65), Vector2(280, 65), Vector2(390, 175), Vector2(505, 120)]
]
const INK := Color("e6ecf4")
const BLUE := Color("67c9f5")
const GREEN := Color("8ad2a3")
const RED := Color("ef8c94")

var equipment: RefCounted
var tool: StringName = &"ring"
var _session: int = -1
var board: Control
var heading: Label
var progress: Label
var feedback: Label
var meter: ProgressBar
var route: Array[Vector2] = []
var stroke: Array[Vector2] = []
var dragging := false
var next_contact := 1
var trace_stage := 0
var trace_bad := false
var _overlays: Array[Node] = []


func setup(params: Dictionary) -> void:
	_clear_trace()
	if equipment != null and _session >= 0:
		equipment.end_repair(_session)
	equipment = params.equipment
	tool = params.get("tool", &"ring")
	_session = equipment.begin_repair(tool)
	if is_node_ready():
		_refresh()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 440)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)
	progress = Label.new()
	column.add_child(progress)
	meter = ProgressBar.new()
	meter.show_percentage = false
	meter.custom_minimum_size.y = 10
	column.add_child(meter)
	var instructions := Label.new()
	instructions.text = "Hold at 1, follow the channel in order, then release at the end."
	column.add_child(instructions)
	board = Control.new()
	board.custom_minimum_size = BOARD
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.draw.connect(_draw_board)
	board.gui_input.connect(_on_board_input)
	column.add_child(board)
	feedback = Label.new()
	feedback.text = "Completed sections are kept. Only an unfinished trace is lost."
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size = Vector2(560, 42)
	column.add_child(feedback)
	var close := Button.new()
	close.text = "Resume / Close · E or Escape"
	close.pressed.connect(_request_close)
	column.add_child(close)
	var footer := Label.new()
	footer.text = "WASD still moves. Enemies keep moving. No repair resource needed."
	footer.add_theme_font_size_override("font_size", 14)
	column.add_child(footer)
	SceneManager.popup_opened.connect(_on_popup_opened)
	_refresh()


func _refresh() -> void:
	if board == null or equipment == null:
		return
	var full: bool = equipment.remaining(tool) >= equipment.capacity(tool) - 0.000001
	var title := "Flash" if tool == &"beam" else String(tool).capitalize()
	heading.text = "Repair · " + title
	if full:
		progress.text = "Ready · %.1f / %.1f" % [equipment.remaining(tool), equipment.capacity(tool)]
	else:
		progress.text = "Completed %d / %d sections · %.1f / %.1f remaining" % [equipment.stage(tool), Tuning.REPAIR_STEPS, equipment.remaining(tool), equipment.capacity(tool)]
	meter.max_value = equipment.capacity(tool)
	meter.value = equipment.remaining(tool)
	route.assign(ROUTES[equipment.stage(tool) % ROUTES.size()])
	board.queue_redraw()


func _input_available() -> bool:
	return not is_queued_for_deletion() and not get_tree().paused and _overlays.is_empty() and not SceneManager.has_popup(&"PauseMenu")


func _can_trace() -> bool:
	return _input_available() and equipment != null and equipment.repairing == tool and equipment.remaining(tool) < equipment.capacity(tool) - 0.000001


func _clear_trace() -> void:
	dragging = false
	stroke.clear()
	next_contact = 1
	trace_bad = false
	if board != null:
		board.queue_redraw()


func _on_popup_opened(_key: StringName, popup: Node) -> void:
	if popup == self:
		return
	_clear_trace()
	_overlays.append(popup)
	popup.tree_exiting.connect(func():
		_overlays.erase(popup)
		_clear_trace())


func _input(event: InputEvent) -> void:
	if not _input_available():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_E, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			_request_close()


func _request_close() -> void:
	if _input_available():
		_clear_trace()
		queue_free()


func _board_scale() -> float:
	return maxf(0.01, minf(board.size.x / BOARD.x, board.size.y / BOARD.y))


func _board_offset() -> Vector2:
	return (board.size - BOARD * _board_scale()) * 0.5


func _on_board_input(event: InputEvent) -> void:
	if not _can_trace():
		_clear_trace()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var point: Vector2 = (event.position - _board_offset()) / _board_scale()
		if event.pressed:
			if dragging:
				return
			_refresh()
			if point.distance_to(route[0]) > CONTACT:
				feedback.text = "Begin inside contact 1. Nothing was lost."
				return
			_clear_trace()
			dragging = true
			trace_stage = equipment.stage(tool)
			stroke = [point]
			feedback.text = "Follow the channel; you may take your time."
		elif dragging:
			_extend_trace(point)
			if dragging:
				if next_contact == route.size() and point.distance_to(route[-1]) <= CONTACT:
					_commit_trace()
				else:
					_invalid("Released early. Completed sections are safe; restart at 1.")
	elif event is InputEventMouseMotion and dragging:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_clear_trace()
			feedback.text = "Mouse released; restart this section at 1."
		else:
			_extend_trace((event.position - _board_offset()) / _board_scale())
	board.queue_redraw()


func _extend_trace(finish: Vector2) -> void:
	var start := stroke[-1]
	var samples := maxi(1, ceili(start.distance_to(finish) / 4.0))
	for i in range(1, samples + 1):
		var point := start.lerp(finish, float(i) / float(samples))
		var nearest := INF
		for segment in range(route.size() - 1):
			nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, route[segment], route[segment + 1])))
		if nearest > CORRIDOR:
			stroke.append(point)
			_invalid("Left the channel. Completed sections are safe; restart at 1.")
			return
		if next_contact < route.size() and point.distance_to(route[next_contact]) <= CONTACT:
			next_contact += 1
			if next_contact == route.size():
				feedback.text = "All contacts joined. Release inside the end circle."
		if stroke[-1].distance_to(point) >= 3.0:
			stroke.append(point)
	if stroke[-1] != finish:
		stroke.append(finish)
	if stroke.size() > 1200:
		stroke = stroke.slice(stroke.size() - 1200)


func _invalid(message: String) -> void:
	dragging = false
	trace_bad = true
	feedback.text = message


func _commit_trace() -> void:
	if not _can_trace() or equipment.stage(tool) != trace_stage:
		_clear_trace()
		return
	var restored: float = equipment.complete_step(tool)
	_clear_trace()
	_refresh()
	feedback.text = "Section complete: restored %.1f. Close now or trace the next section." % restored
	if equipment.remaining(tool) >= equipment.capacity(tool) - 0.000001:
		feedback.text = "Ready. Close to resume using this item."


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_trace()


func _exit_tree() -> void:
	if equipment != null:
		equipment.end_repair(_session)


func _draw_board() -> void:
	board.draw_rect(Rect2(Vector2.ZERO, board.size), Color("101722"))
	if route.is_empty():
		return
	board.draw_set_transform(_board_offset(), 0, Vector2.ONE * _board_scale())
	var full: bool = equipment.remaining(tool) >= equipment.capacity(tool) - 0.000001
	for i in range(route.size() - 1):
		board.draw_line(route[i], route[i + 1], Color("294354"), CORRIDOR * 2, true)
	for point in route:
		board.draw_circle(point, CORRIDOR, Color("294354"))
	for i in range(route.size() - 1):
		board.draw_dashed_line(route[i], route[i + 1], INK.darkened(0.4), 1, 7, true)
	if stroke.size() > 1:
		board.draw_polyline(PackedVector2Array(stroke), RED if trace_bad else GREEN, 4, true)
	for i in range(route.size()):
		var color := GREEN if full or (dragging and i < next_contact) else BLUE
		board.draw_circle(route[i], CONTACT, color.darkened(0.65))
		board.draw_arc(route[i], CONTACT, 0, TAU, 28, color, 2, true)
		board.draw_string(ThemeDB.fallback_font, route[i] + Vector2(-6, 6), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, INK)
