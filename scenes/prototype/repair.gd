extends Control

const Tuning = preload("res://scenes/prototype/tuning.gd")
const BOARD := Vector2(520, 196)
const PANEL_MIN_SIZE := Vector2(404, 226)
const BOARD_MIN_SIZE := Vector2(378, 130)
const CORRIDOR := 22.0
const CONTACT := 18.0
# Four connected quarter sections forming one continuous fixed path (4 * 184 = 736 units).
const ROUTES := [
	[Vector2(36, 98), Vector2(68, 38), Vector2(116, 38), Vector2(148, 98)],
	[Vector2(148, 98), Vector2(180, 158), Vector2(228, 158), Vector2(260, 98)],
	[Vector2(260, 98), Vector2(292, 38), Vector2(340, 38), Vector2(372, 98)],
	[Vector2(372, 98), Vector2(404, 158), Vector2(452, 158), Vector2(484, 98)]
]
const INK := Color("e6ecf4")
const BLUE := Color("67c9f5")
const GREEN := Color("8ad2a3")
const RED := Color("ef8c94")

var equipment: RefCounted
var tool: StringName = &"ring"
var _session: int = -1
var panel: PanelContainer
var board: Control
var heading: Label
var progress: Label
var feedback: Label
var meter: ProgressBar
var full_path: Array[Vector2] = []
var solved_path: Array[Vector2] = []
var missing_path: Array[Vector2] = []
var future_missing_path: Array[Vector2] = []
var route: Array[Vector2] = []
var stroke: Array[Vector2] = []
var dragging := false
var next_contact := 1
var trace_stage := 0
var trace_bad := false
var _overlays: Array[Node] = []


func _init() -> void:
	_build_full_path()


func _build_full_path() -> void:
	full_path.clear()
	for section_idx in range(ROUTES.size()):
		var section: Array = ROUTES[section_idx]
		for point_idx in range(section.size()):
			if section_idx > 0 and point_idx == 0:
				continue
			full_path.append(section[point_idx])


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
	if get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling is ColorRect:
				sibling.color = Color(0.0, 0.0, 0.0, 0.08)
	panel = PanelContainer.new()
	panel.custom_minimum_size = PANEL_MIN_SIZE
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(0.10, 0.14, 0.18, 0.90)
	backdrop.border_color = Color("475361")
	backdrop.set_border_width_all(1)
	backdrop.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", backdrop)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	column.add_child(header_row)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 17)
	header_row.add_child(heading)
	progress = Label.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress.add_theme_font_size_override("font_size", 13)
	header_row.add_child(progress)
	meter = ProgressBar.new()
	meter.show_percentage = false
	meter.custom_minimum_size.y = 6
	column.add_child(meter)
	var instructions := Label.new()
	instructions.text = "Hold at 1, trace missing section in order, release at checkpoint."
	instructions.add_theme_font_size_override("font_size", 12)
	column.add_child(instructions)
	board = Control.new()
	board.custom_minimum_size = BOARD_MIN_SIZE
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.draw.connect(_draw_board)
	board.gui_input.connect(_on_board_input)
	column.add_child(board)
	feedback = Label.new()
	feedback.text = "Hold E to repair · release E or Esc to close · WASD still moves."
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size = Vector2(378, 18)
	feedback.add_theme_font_size_override("font_size", 12)
	column.add_child(feedback)
	resized.connect(_update_layout)
	get_viewport().size_changed.connect(_update_layout)
	SceneManager.popup_opened.connect(_on_popup_opened)
	_update_layout()
	_refresh()


func _update_layout() -> void:
	if panel == null:
		return
	var view_size := size if size.x > 0.0 and size.y > 0.0 else get_viewport_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		view_size = Vector2(960, 600)
	var safe_size := Vector2(minf(view_size.x, 960.0), minf(view_size.y, 600.0))
	var target_size := Vector2(
		clampf(safe_size.x * 0.42, 340.0, 404.0),
		clampf(safe_size.y * 0.38, 210.0, 228.0)
	)
	var edge_margin := 16.0
	panel.size = target_size
	panel.position = Vector2(
		maxf(edge_margin, safe_size.x - target_size.x - edge_margin),
		edge_margin
	)


func path_length(points: Array[Vector2]) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


func _slice_polyline(points: Array[Vector2], start_frac: float, end_frac: float, min_vertex_gap: float = 0.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if points.size() < 2:
		return out
	var f0 := clampf(start_frac, 0.0, 1.0)
	var f1 := clampf(end_frac, 0.0, 1.0)
	if f1 <= f0 + 0.000001:
		return out
	if f0 <= 0.0001 and f1 >= 0.9999 and min_vertex_gap <= 0.0:
		out.assign(points)
		return out
	var total := path_length(points)
	if total <= 0.000001:
		return out
	var d0 := f0 * total
	var d1 := f1 * total
	var raw: Array[Vector2] = []
	var accum := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg := a.distance_to(b)
		var next_accum := accum + seg
		if seg > 0.000001:
			if d0 >= accum - 0.0001 and d0 <= next_accum + 0.0001 and raw.is_empty():
				var t0 := clampf((d0 - accum) / seg, 0.0, 1.0)
				raw.append(a.lerp(b, t0))
			if not raw.is_empty() and d1 > next_accum + 0.0001:
				if raw[-1].distance_to(b) > 0.01:
					raw.append(b)
			if d1 >= accum - 0.0001 and d1 <= next_accum + 0.0001:
				var t1 := clampf((d1 - accum) / seg, 0.0, 1.0)
				var end_pt := a.lerp(b, t1)
				if raw.is_empty() or raw[-1].distance_to(end_pt) > 0.01:
					raw.append(end_pt)
				break
		accum = next_accum
	if raw.size() < 2:
		return out
	out.append(raw[0])
	for i in range(1, raw.size() - 1):
		if min_vertex_gap > 0.0 and (out[-1].distance_to(raw[i]) < min_vertex_gap or raw[i].distance_to(raw[-1]) < min_vertex_gap):
			continue
		out.append(raw[i])
	out.append(raw[-1])
	return out


func _refresh() -> void:
	if board == null or equipment == null:
		return
	var cap: float = equipment.capacity(tool)
	var rem: float = equipment.remaining(tool)
	var cond: float = equipment.condition(tool)
	var full: bool = equipment.is_full(tool)
	var title := "Flash" if tool == &"beam" else String(tool).capitalize()
	heading.text = "Repair · " + title
	if full:
		progress.text = "Ready · %.1f / %.1f" % [rem, cap]
		solved_path.assign(full_path)
		missing_path.clear()
		future_missing_path.clear()
		route.assign(ROUTES[0])
	else:
		var s: int = equipment.stage(tool)
		var steps: int = Tuning.REPAIR_STEPS
		progress.text = "%d / %d · %.1f / %.1f" % [s, steps, rem, cap]
		solved_path = _slice_polyline(full_path, 0.0, cond)
		missing_path = _slice_polyline(full_path, cond, 1.0)
		var q_start := float(s) / float(steps)
		var q_end := float(s + 1) / float(steps)
		future_missing_path = _slice_polyline(full_path, q_end, 1.0)
		var local_intact := clampf((cond - q_start) / maxf(0.0001, q_end - q_start), 0.0, 1.0)
		if local_intact <= 0.0001:
			route.assign(ROUTES[s % ROUTES.size()])
		else:
			var section_points: Array[Vector2] = []
			section_points.assign(ROUTES[s % ROUTES.size()])
			route = _slice_polyline(section_points, minf(local_intact, 0.82), 1.0, CONTACT * 0.75)
	meter.max_value = cap
	meter.value = rem
	board.queue_redraw()


func _input_available() -> bool:
	return not is_queued_for_deletion() and not get_tree().paused and _overlays.is_empty() and not SceneManager.has_popup(&"PauseMenu")


func _can_trace() -> bool:
	return (
		_input_available()
		and equipment != null
		and equipment.is_session_active(_session, tool)
		and not equipment.is_full(tool)
	)


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
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code == KEY_E:
			get_viewport().set_input_as_handled()
			if not event.pressed and not event.echo:
				_request_close()
		elif code == KEY_ESCAPE and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			_request_close()


func _request_close() -> void:
	if not _input_available():
		return
	_clear_trace()
	if equipment != null:
		equipment.end_repair(_session)
	var holder := get_parent()
	if holder != null and SceneManager._popups.has(holder) and SceneManager._popups.back() == holder:
		SceneManager.close_popup(&"Repair")
	elif not is_queued_for_deletion():
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
			if route.is_empty() or point.distance_to(route[0]) > CONTACT:
				feedback.text = "Begin inside contact 1. Nothing was lost."
				return
			_clear_trace()
			dragging = true
			trace_stage = equipment.stage(tool)
			stroke = [point]
			feedback.text = "Follow the channel; release at the checkpoint."
		elif dragging:
			_extend_trace(point)
			if dragging:
				if next_contact == route.size() and point.distance_to(route[-1]) <= CONTACT:
					_commit_trace()
				else:
					_invalid("Released early. Completed checkpoints are safe; restart at 1.")
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
			_invalid("Left the channel. Completed checkpoints are safe; restart at 1.")
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
	var restored: float = equipment.complete_step(tool, _session)
	if restored <= 0.0:
		_clear_trace()
		return
	_clear_trace()
	_refresh()
	if equipment.is_full(tool):
		feedback.text = "Ready. Repair complete."
		_request_close()
	else:
		feedback.text = "Checkpoint complete: restored %.1f. Trace next or release E." % restored


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_trace()


func _exit_tree() -> void:
	if equipment != null:
		equipment.end_repair(_session)


func _draw_board() -> void:
	board.draw_rect(Rect2(Vector2.ZERO, board.size), Color(0.06, 0.09, 0.14, 0.92))
	if route.is_empty() and solved_path.is_empty():
		return
	board.draw_set_transform(_board_offset(), 0, Vector2.ONE * _board_scale())
	var full: bool = equipment != null and equipment.is_full(tool)
	# 1. Draw remaining missing path beyond the next checkpoint (dimmed preview).
	if future_missing_path.size() > 1:
		for i in range(future_missing_path.size() - 1):
			board.draw_line(future_missing_path[i], future_missing_path[i + 1], Color("182632"), CORRIDOR * 1.5, true)
			board.draw_dashed_line(future_missing_path[i], future_missing_path[i + 1], INK.darkened(0.65), 1.0, 7.0, true)
	# 2. Draw already-solved path prefix (intact condition).
	if solved_path.size() > 1:
		for i in range(solved_path.size() - 1):
			board.draw_line(solved_path[i], solved_path[i + 1], Color("1d3a34"), CORRIDOR * 1.5, true)
		board.draw_polyline(PackedVector2Array(solved_path), GREEN.darkened(0.15), 3.0, true)
	# 3. Draw quarter checkpoint markers along the fixed path.
	for section in ROUTES:
		var cp: Vector2 = section[-1]
		board.draw_arc(cp, CONTACT * 0.65, 0, TAU, 20, INK.darkened(0.55), 1.5, true)
	# 4. Draw active missing section up to the next checkpoint.
	if not full and route.size() > 1:
		for i in range(route.size() - 1):
			board.draw_line(route[i], route[i + 1], Color("294354"), CORRIDOR * 2.0, true)
		for point in route:
			board.draw_circle(point, CORRIDOR, Color("294354"))
		for i in range(route.size() - 1):
			board.draw_dashed_line(route[i], route[i + 1], INK.darkened(0.35), 1.0, 7.0, true)
		if stroke.size() > 1:
			board.draw_polyline(PackedVector2Array(stroke), RED if trace_bad else GREEN, 4.0, true)
		for i in range(route.size()):
			var color := GREEN if (dragging and i < next_contact) else BLUE
			board.draw_circle(route[i], CONTACT, color.darkened(0.65))
			board.draw_arc(route[i], CONTACT, 0, TAU, 24, color, 2.0, true)
			board.draw_string(ThemeDB.fallback_font, route[i] + Vector2(-5, 6), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
