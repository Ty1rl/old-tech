extends Control

const Tuning = preload("res://scenes/prototype/tuning.gd")
const Gestures = preload("res://scenes/prototype/repair_gestures.gd")
const ToolModels := {
	"ring": preload("res://assets/equipment/ring_caster.glb"),
	"beam": preload("res://assets/equipment/flash_camera.glb"),
	"cone": preload("res://assets/equipment/heat_bellows.glb"),
	"clock": preload("res://assets/equipment/time_device.glb"),
}

const BOARD := Vector2(520.0, 260.0)
const PANEL_MIN_SIZE := Vector2(404.0, 226.0)
const BOARD_MIN_SIZE := Vector2(378.0, 130.0)
const CORRIDOR := Gestures.TRACE_CORRIDOR
const CONTACT := Gestures.TRACE_CONTACT

const INK := Color("e6ecf4")
const BLUE := Color("67c9f5")
const GREEN := Color("8ad2a3")
const RED := Color("ef8c94")
const YELLOW := Color("f5d76e")
const PURPLE := Color("c394f7")
const ORANGE := Color("f59b56")

var ROUTES: Array = []
var equipment: RefCounted
var tool: StringName = &"ring"
var _session: int = -1
var panel: PanelContainer
var board: Control
var overlay: Control
var viewport_container: SubViewportContainer
var sub_viewport: SubViewport
var preview_cam: Camera3D
var model_instances: Dictionary = {}
var heading: Label
var instructions: Label
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
var active_op_index := 0
var active_op: Dictionary = {}
var active_kind: StringName = &"spin"
var local_intact_ratio := 0.0

var spin_accum := 0.0
var spin_required := Gestures.SPIN_FULL_RADIANS
var spin_locked_dir := 0.0
var spin_visual_angle := 0.0

var connected_pairs: Array[int] = []
var selected_terminal: Dictionary = {}
var _drag_pair_pending: int = -1
var _drag_completed_pairs: Array[int] = []
var _overlays: Array[Node] = []


func _init() -> void:
	_rebuild_routes_for_tool(tool)


func _rebuild_routes_for_tool(for_tool: StringName) -> void:
	ROUTES = Gestures.canonical_stage_routes(for_tool)
	full_path.clear()
	for section_idx in range(ROUTES.size()):
		var section: Array = ROUTES[section_idx]
		for point_idx in range(section.size()):
			if section_idx > 0 and point_idx == 0 and not full_path.is_empty() and full_path[-1].distance_to(section[point_idx]) < 0.5:
				continue
			full_path.append(section[point_idx])


func setup(params: Dictionary) -> void:
	_clear_trace()
	if equipment != null and _session >= 0:
		equipment.end_repair(_session)
	equipment = params.equipment
	tool = params.get("tool", &"ring")
	_rebuild_routes_for_tool(tool)
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
	backdrop.bg_color = Color(0.09, 0.12, 0.16, 0.92)
	backdrop.border_color = Color("4b5968")
	backdrop.set_border_width_all(1)
	backdrop.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", backdrop)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	column.add_child(header_row)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 16)
	header_row.add_child(heading)
	progress = Label.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress.add_theme_font_size_override("font_size", 12)
	header_row.add_child(progress)
	meter = ProgressBar.new()
	meter.show_percentage = false
	meter.custom_minimum_size.y = 5
	column.add_child(meter)
	instructions = Label.new()
	instructions.text = "Spin, trace, or connect the highlighted mechanism."
	instructions.add_theme_font_size_override("font_size", 11)
	column.add_child(instructions)
	board = Control.new()
	board.custom_minimum_size = BOARD_MIN_SIZE
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.clip_contents = true
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.draw.connect(_draw_board)
	board.gui_input.connect(_on_board_input)
	column.add_child(board)
	_build_tool_viewport()
	overlay = Control.new()
	overlay.name = "GestureOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	board.add_child(overlay)
	feedback = Label.new()
	feedback.text = "Hold E to repair · release E or Esc to close · WASD still moves."
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size = Vector2(378, 16)
	feedback.add_theme_font_size_override("font_size", 11)
	column.add_child(feedback)
	resized.connect(_update_layout)
	get_viewport().size_changed.connect(_update_layout)
	var sm := _scene_manager()
	if sm != null and sm.has_signal("popup_opened"):
		sm.connect("popup_opened", _on_popup_opened)
	_update_layout()
	_refresh()


func _scene_manager() -> Node:
	return get_tree().root.get_node_or_null("SceneManager") if is_inside_tree() and get_tree() != null else null


func _build_tool_viewport() -> void:
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "ToolBackdropViewport"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(viewport_container)

	sub_viewport = SubViewport.new()
	sub_viewport.own_world_3d = true
	sub_viewport.transparent_bg = true
	sub_viewport.size = Vector2i(int(BOARD.x), int(BOARD.y))
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(sub_viewport)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 1.15
	env_node.environment = env
	sub_viewport.add_child(env_node)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	key_light.light_energy = 1.65
	key_light.light_color = Color(1.0, 0.97, 0.92)
	sub_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-28.0, -125.0, 0.0)
	fill_light.light_energy = 0.85
	fill_light.light_color = Color(0.78, 0.86, 0.98)
	sub_viewport.add_child(fill_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(18.0, 165.0, 0.0)
	rim_light.light_energy = 0.95
	rim_light.light_color = Color(0.95, 0.90, 0.82)
	sub_viewport.add_child(rim_light)

	preview_cam = Camera3D.new()
	preview_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview_cam.size = 0.60
	preview_cam.position = Vector3(0.0, 1.25, 1.35)
	preview_cam.look_at_from_position(preview_cam.position, Vector3.ZERO, Vector3.UP)
	sub_viewport.add_child(preview_cam)

	for key in ToolModels.keys():
		var holder := Node3D.new()
		holder.name = "Model_" + String(key)
		var inst: Node3D = ToolModels[key].instantiate()
		holder.add_child(inst)
		holder.visible = false
		sub_viewport.add_child(holder)
		model_instances[key] = holder


func _update_3d_backdrop() -> void:
	if preview_cam == null:
		return
	var spec := Gestures.tool_spec(tool)
	var active_key := String(spec["id"])
	for key in model_instances.keys():
		var holder: Node3D = model_instances[key]
		holder.visible = (key == active_key)
		if holder.visible:
			holder.position = spec["model_pos"]
			holder.rotation_degrees = spec["model_rot_deg"]
			_animate_model_parts(holder, active_key)
	preview_cam.position = spec["cam_pos"]
	preview_cam.size = float(spec["cam_size"])
	preview_cam.look_at_from_position(preview_cam.position, spec["cam_target"], Vector3.UP)


func _animate_model_parts(holder: Node3D, key: String) -> void:
	if key == "ring":
		var saw := holder.find_child("Suspended_Saw_Ring", true, false) as Node3D
		if saw != null:
			saw.rotation.y = spin_visual_angle * 0.65
		var crank := holder.find_child("Handwheel_Crank", true, false) as Node3D
		if crank != null:
			crank.rotation.x = spin_visual_angle
	elif key == "beam":
		var lens := holder.find_child("Lens_Glass_Element", true, false) as Node3D
		if lens != null:
			lens.rotation.z = spin_visual_angle
	elif key == "clock":
		var rod := holder.find_child("Metronome_Pendulum_Rod", true, false) as Node3D
		if rod != null:
			rod.rotation.z = sin(spin_visual_angle) * 0.22


var preview_rect := Rect2()


func _update_layout() -> void:
	if panel == null:
		return
	if preview_rect.size.x > 0.0 and preview_rect.size.y > 0.0:
		panel.position = preview_rect.position
		panel.size = preview_rect.size
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
	return Gestures.path_length(points)


func _slice_polyline(points: Array[Vector2], start_frac: float, end_frac: float, min_vertex_gap: float = 0.0) -> Array[Vector2]:
	return Gestures.slice_polyline(points, start_frac, end_frac, min_vertex_gap)


func _queue_redraws() -> void:
	if board != null:
		board.queue_redraw()
	if overlay != null:
		overlay.queue_redraw()


func _refresh() -> void:
	if board == null or equipment == null:
		return
	_rebuild_routes_for_tool(tool)
	var spec := Gestures.tool_spec(tool)
	var cap: float = equipment.capacity(tool)
	var rem: float = equipment.remaining(tool)
	var cond: float = equipment.condition(tool)
	var full: bool = equipment.is_full(tool)
	heading.text = "Repair · " + String(spec["title"])
	if full:
		active_op_index = 3
		active_op = spec["operations"][2]
		active_kind = active_op["kind"]
		progress.text = "Ready · %.1f / %.1f" % [rem, cap]
		instructions.text = "All mechanisms aligned and ready."
		solved_path.assign(full_path)
		missing_path.clear()
		future_missing_path.clear()
		route.assign(ROUTES[0])
	else:
		var s: int = equipment.stage(tool)
		var steps: int = Tuning.REPAIR_STEPS
		active_op_index = Gestures.operation_index_for_stage(s)
		active_op = Gestures.active_operation(tool, s)
		active_kind = active_op["kind"]
		progress.text = "Op %d/3 (%d / %d) · %.1f / %.1f" % [active_op_index + 1, s, steps, rem, cap]
		instructions.text = String(active_op.get("prompt", "Complete the highlighted repair gesture."))
		solved_path = _slice_polyline(full_path, 0.0, cond)
		missing_path = _slice_polyline(full_path, cond, 1.0)
		var q_start := float(s) / float(steps)
		var q_end := float(s + 1) / float(steps)
		future_missing_path = _slice_polyline(full_path, q_end, 1.0)
		local_intact_ratio = clampf((cond - q_start) / maxf(0.0001, q_end - q_start), 0.0, 1.0)
		_prepare_active_operation_geometry(s, local_intact_ratio)
	meter.max_value = cap
	meter.value = rem
	_update_3d_backdrop()
	_queue_redraws()


func _prepare_active_operation_geometry(stage_idx: int, local_intact: float) -> void:
	var base_route: Array[Vector2] = []
	base_route.assign(ROUTES[stage_idx % ROUTES.size()])
	if active_kind == &"spin":
		spin_required = Gestures.spin_required_radians(local_intact)
		if local_intact <= 0.0001:
			route.assign(base_route)
		else:
			route = _slice_polyline(base_route, minf(local_intact, 0.82), 1.0)
	elif active_kind == &"trace":
		if local_intact <= 0.0001:
			route.assign(base_route)
		else:
			route = _slice_polyline(base_route, minf(local_intact, 0.82), 1.0, CONTACT * 0.75)
	elif active_kind == &"connect":
		connected_pairs.clear()
		if stage_idx == 3:
			# Pair 0 (▲A) is already restored at checkpoint 3 (75%); only Pair 1 (■B) remains!
			connected_pairs.append(0)
		elif local_intact >= 0.55 and active_op.get("pairs", []).size() >= 2:
			connected_pairs.append(0)
		route.assign(base_route)


func _input_available() -> bool:
	var sm := _scene_manager()
	var has_pause := bool(sm.call("has_popup", &"PauseMenu")) if sm != null else false
	return not is_queued_for_deletion() and not get_tree().paused and _overlays.is_empty() and not has_pause


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
	spin_accum = 0.0
	spin_locked_dir = 0.0
	selected_terminal = {}
	_drag_pair_pending = -1
	_drag_completed_pairs.clear()
	_queue_redraws()


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
	var sm := _scene_manager()
	var popups: Variant = sm.get("_popups") if sm != null else null
	if holder != null and popups is Array and (popups as Array).has(holder) and (popups as Array).back() == holder:
		sm.call("close_popup", &"Repair")
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
		if active_kind == &"spin":
			_handle_spin_button(point, event.pressed)
		elif active_kind == &"connect":
			_handle_connect_button(point, event.pressed)
		else:
			_handle_trace_button(point, event.pressed)
	elif event is InputEventMouseMotion and dragging:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_clear_trace()
			feedback.text = "Mouse released; restart this gesture."
		else:
			var point: Vector2 = (event.position - _board_offset()) / _board_scale()
			if active_kind == &"spin":
				_extend_spin(point)
			elif active_kind == &"connect":
				_extend_connect(point)
			else:
				_extend_trace(point)
	_queue_redraws()


# --- SPIN GESTURE ---
func _handle_spin_button(point: Vector2, pressed: bool) -> void:
	if pressed:
		if dragging:
			return
		_refresh()
		if not Gestures.spin_can_start(active_op, point):
			feedback.text = "Grab the spin ring to rotate the mechanism. Nothing was lost."
			return
		_clear_trace()
		dragging = true
		trace_stage = equipment.stage(tool)
		stroke = [point]
		feedback.text = "Drag smoothly around the ring to spin."
	elif dragging:
		_extend_spin(point)
		if dragging:
			if spin_accum >= spin_required - 0.06:
				_commit_steps(1)
			else:
				var pct := int(round(clampf(spin_accum / maxf(0.01, spin_required), 0.0, 1.0) * 100.0))
				_invalid("Released early (%d%% spun). Completed checkpoints are safe; spin further." % pct)


func _extend_spin(finish: Vector2) -> void:
	var start := stroke[-1]
	var res := Gestures.spin_step(active_op, start, finish, spin_accum, spin_locked_dir)
	if not bool(res["ok"]):
		stroke.append(res["point"])
		_invalid(String(res["message"]))
		return
	spin_accum = float(res["accum"])
	spin_locked_dir = float(res["locked_dir"])
	spin_visual_angle += (spin_accum * 0.25)
	_update_3d_backdrop()
	if stroke[-1].distance_to(finish) >= 3.0:
		stroke.append(finish)
	if spin_accum >= spin_required - 0.06:
		feedback.text = "Spin target reached. Release to lock."


# --- TRACE GESTURE ---
func _handle_trace_button(point: Vector2, pressed: bool) -> void:
	if pressed:
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
		feedback.text = "Follow the trace channel in order; release at the end mark."
	elif dragging:
		_extend_trace(point)
		if dragging:
			if next_contact == route.size() and point.distance_to(route[-1]) <= CONTACT:
				# On Blue (ring) and Yellow (beam), Operation 3 (stage == 2) is the final visible operation;
				# completing the full trace from start to end restores both remaining internal quarters (50% -> 100%).
				var steps_to_award := 2 if (active_op_index == 2 and trace_stage == 2) else 1
				_commit_steps(steps_to_award)
			elif active_op_index == 2 and trace_stage == 2 and route.size() >= 3 and next_contact >= 3 and point.distance_to(route[2]) <= CONTACT:
				# Releasing at the midpoint checkpoint of Operation 3 saves Checkpoint 3 (75%)!
				_commit_steps(1)
			else:
				_invalid("Released early. Completed checkpoints are safe; restart at 1.")


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


# --- CONNECT GESTURE ---
func _handle_connect_button(point: Vector2, pressed: bool) -> void:
	var term := Gestures.find_terminal(active_op, point)
	if pressed:
		if dragging:
			return
		trace_bad = false
		trace_stage = equipment.stage(tool)
		if selected_terminal.is_empty():
			if term.is_empty() or int(term["pair_index"]) in connected_pairs:
				_invalid("Click an unconnected ▲A or ■B contact terminal. Nothing was lost.")
				return
			selected_terminal = term
			dragging = true
			_drag_pair_pending = -1
			_drag_completed_pairs.clear()
			stroke = [Vector2(term["position"])]
			feedback.text = "Selected %s (%s). Click matching %s terminal." % [term["label"], term["shape"], term["label"]]
		else:
			if term.is_empty() or int(term["pair_index"]) in connected_pairs:
				selected_terminal = {}
				_invalid("Missed matching terminal. Select a contact pair again.")
				return
			if int(term["pair_index"]) == int(selected_terminal["pair_index"]) and String(term["side"]) == String(selected_terminal["side"]):
				dragging = true
				stroke = [Vector2(term["position"])]
				feedback.text = "Click the opposite matching %s terminal." % String(term["label"])
				return
			if Gestures.terminals_match(selected_terminal, term):
				dragging = true
				_drag_pair_pending = int(term["pair_index"])
				stroke = [Vector2(selected_terminal["position"]), Vector2(term["position"])]
				feedback.text = "Matched %s pair! Release to connect." % String(term["label"])
			else:
				var prev_lbl := String(selected_terminal.get("label", "?"))
				var new_lbl := String(term.get("label", "?"))
				selected_terminal = {}
				_invalid("Mismatched terminal (%s vs %s). Match shape and label (▲A to ▲A, ■B to ■B)." % [prev_lbl, new_lbl])
	elif dragging:
		_extend_connect(point)
		if not dragging:
			return
		var rel_term := Gestures.find_terminal(active_op, point)
		if _drag_pair_pending >= 0 and not rel_term.is_empty() and int(rel_term["pair_index"]) == _drag_pair_pending:
			dragging = false
			var to_commit: Array[int] = _drag_completed_pairs.duplicate()
			if not (_drag_pair_pending in to_commit):
				to_commit.append(_drag_pair_pending)
			selected_terminal = {}
			_drag_pair_pending = -1
			_drag_completed_pairs.clear()
			stroke.clear()
			_commit_connect_pairs(to_commit)
		elif not rel_term.is_empty() and not selected_terminal.is_empty() and int(rel_term["pair_index"]) == int(selected_terminal["pair_index"]) and String(rel_term["side"]) == String(selected_terminal["side"]) and _drag_completed_pairs.is_empty():
			# Clicked and released on the first terminal: keep it selected for the second click!
			dragging = false
			stroke = [Vector2(selected_terminal["position"])]
			feedback.text = "Terminal %s selected. Now click the matching %s terminal." % [selected_terminal["label"], selected_terminal["label"]]
		else:
			selected_terminal = {}
			_drag_pair_pending = -1
			_drag_completed_pairs.clear()
			_invalid("Release on the matching terminal to complete the connection.")


func _extend_connect(finish: Vector2) -> void:
	if not Gestures.point_near_connect_corridor(active_op, finish):
		stroke.append(finish)
		selected_terminal = {}
		_drag_pair_pending = -1
		_drag_completed_pairs.clear()
		_invalid("Left the terminal area. Completed checkpoints are safe.")
		return
	var hit_term := Gestures.find_terminal(active_op, finish)
	if not hit_term.is_empty():
		var hit_idx := int(hit_term["pair_index"])
		if not (hit_idx in connected_pairs):
			if not selected_terminal.is_empty() and Gestures.terminals_match(selected_terminal, hit_term):
				_drag_pair_pending = hit_idx
			elif _drag_pair_pending >= 0 and hit_idx != _drag_pair_pending and not (hit_idx in _drag_completed_pairs):
				_drag_completed_pairs.append(_drag_pair_pending)
				selected_terminal = hit_term
				_drag_pair_pending = -1
	if stroke.is_empty() or stroke[-1].distance_to(finish) >= 3.0:
		stroke.append(finish)


func _commit_connect_pairs(pair_indices: Array[int]) -> void:
	if not _can_trace() or equipment.stage(tool) != trace_stage:
		_clear_trace()
		return
	var pairs: Array = active_op.get("pairs", [])
	var newly_added := 0
	for idx in pair_indices:
		if not (idx in connected_pairs):
			connected_pairs.append(idx)
			newly_added += 1
	if newly_added <= 0:
		return
	if active_op_index == 2:
		# Operation 3 Connect (Orange cone & Purple clock): each connected pair restores 1 checkpoint (50%->75%, 75%->100%)
		_commit_steps(newly_added)
	else:
		# Operation 2 Connect (Blue ring & Yellow beam): connecting all pairs in Operation 2 restores Checkpoint 2 (25%->50%)
		if connected_pairs.size() >= pairs.size():
			_commit_steps(1)
		else:
			var remaining_lbl := "■B" if (0 in connected_pairs) else "▲A"
			feedback.text = "Pair connected! Now click the matching %s terminals." % remaining_lbl
			_queue_redraws()


func _invalid(message: String) -> void:
	dragging = false
	trace_bad = true
	feedback.text = message
	_queue_redraws()


func _commit_steps(step_count: int) -> void:
	if not _can_trace() or equipment.stage(tool) != trace_stage:
		_clear_trace()
		return
	var total_restored := 0.0
	for _i in range(maxi(1, step_count)):
		if equipment.is_full(tool):
			break
		var r: float = equipment.complete_step(tool, _session)
		if r <= 0.0:
			break
		total_restored += r
	if total_restored <= 0.0:
		_clear_trace()
		return
	spin_visual_angle += 0.85
	_clear_trace()
	_refresh()
	if equipment.is_full(tool):
		feedback.text = "Ready. Repair complete."
		_request_close()
	else:
		feedback.text = "Checkpoint complete (+%.1f). Next operation ready or release E." % total_restored


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_trace()


func _exit_tree() -> void:
	if equipment != null:
		equipment.end_repair(_session)


func _draw_board() -> void:
	board.draw_rect(Rect2(Vector2.ZERO, board.size), Color(0.07, 0.10, 0.14, 0.96))
	board.draw_set_transform(_board_offset(), 0, Vector2.ONE * _board_scale())
	# Subtle workshop blueprint grid behind the 3D SubViewport
	var grid_col := Color(0.16, 0.22, 0.29, 0.35)
	for gx in range(0, int(BOARD.x) + 1, 40):
		board.draw_line(Vector2(gx, 0), Vector2(gx, BOARD.y), grid_col, 1.0)
	for gy in range(0, int(BOARD.y) + 1, 40):
		board.draw_line(Vector2(0, gy), Vector2(BOARD.x, gy), grid_col, 1.0)


func _draw_overlay() -> void:
	if equipment == null:
		return
	overlay.draw_set_transform(_board_offset(), 0, Vector2.ONE * _board_scale())
	var spec := Gestures.tool_spec(tool)
	var ops: Array = spec["operations"]
	var full: bool = equipment.is_full(tool)

	# 1. Tool-specific mechanical backdrop details (including open fan cover & open front grille on Orange cone)
	_draw_tool_backdrop_details(String(spec["id"]))

	# 2. Draw all 3 operations on the tool so completed work, active gesture, and upcoming steps are legible
	for op_idx in range(ops.size()):
		var op: Dictionary = ops[op_idx]
		var is_done := full or (op_idx < active_op_index)
		var is_active := (not full) and (op_idx == active_op_index)
		_draw_operation_layer(op, is_done, is_active)

	# 3. Draw top 3-step operation bar
	_draw_operation_pills(ops, full)


func _draw_tool_backdrop_details(tool_key: String) -> void:
	if tool_key == "cone":
		# Orange Heat Bellows: visually open rear fan cover & open front nozzle grille per mockup 5.png
		var fan_c := Vector2(412.0, 112.0)
		# Open hinged rear fan lid swung up-right
		var lid_c := fan_c + Vector2(64.0, -42.0)
		overlay.draw_circle(lid_c, 34.0, Color("445244"))
		overlay.draw_arc(lid_c, 34.0, 0.0, TAU, 28, Color("7b8c79"), 2.5, true)
		overlay.draw_rect(Rect2(fan_c + Vector2(24.0, -24.0), Vector2(18.0, 10.0)), Color("5c695b"))
		# Exposed rear fan housing & rotating 6-blade fan inside
		overlay.draw_circle(fan_c, 38.0, Color(0.08, 0.10, 0.12, 0.88))
		for b_idx in range(6):
			var ang := spin_visual_angle + float(b_idx) * TAU / 6.0
			var b_tip := fan_c + Vector2(cos(ang), sin(ang)) * 28.0
			var b_side := fan_c + Vector2(cos(ang + 0.35), sin(ang + 0.35)) * 18.0
			overlay.draw_colored_polygon(PackedVector2Array([fan_c, b_tip, b_side]), Color("58646e"))
		overlay.draw_circle(fan_c, 7.0, Color("c49b45"))

		# Open front nozzle hood + hinged front grille swung down-left exposing glowing orange heating coils
		var hood_rect := Rect2(Vector2(66.0, 112.0), Vector2(110.0, 92.0))
		overlay.draw_rect(hood_rect, Color(0.10, 0.11, 0.13, 0.85))
		overlay.draw_rect(hood_rect, Color("8c6d32"), false, 2.5)
		# Swung-open bottom grille grate
		var grille_pts := PackedVector2Array([
			Vector2(66.0, 204.0),
			Vector2(176.0, 204.0),
			Vector2(156.0, 244.0),
			Vector2(46.0, 238.0),
		])
		overlay.draw_colored_polygon(grille_pts, Color(0.15, 0.18, 0.22, 0.90))
		overlay.draw_polyline(PackedVector2Array([grille_pts[0], grille_pts[1], grille_pts[2], grille_pts[3], grille_pts[0]]), Color("637282"), 2.0, true)
		for g_idx in range(1, 4):
			var t := float(g_idx) / 4.0
			overlay.draw_line(grille_pts[0].lerp(grille_pts[3], t), grille_pts[1].lerp(grille_pts[2], t), Color("4d5966"), 1.5)
		# Glowing orange ceramic heating coils inside open hood
		for row_y in [138.0, 160.0, 180.0]:
			overlay.draw_line(Vector2(78.0, row_y - 2.0), Vector2(116.0, row_y + 1.0), ORANGE, 7.0, true)
			overlay.draw_line(Vector2(130.0, row_y + 2.0), Vector2(166.0, row_y + 5.0), ORANGE, 7.0, true)
	elif tool_key == "ring":
		# Highlight cassette tape reels inside open top gearbox for "WIND TAPE"
		var c1 := Vector2(194.0, 74.0)
		var c2 := Vector2(236.0, 84.0)
		overlay.draw_circle(c1, 22.0, Color(0.38, 0.25, 0.18, 0.85))
		overlay.draw_circle(c2, 20.0, Color(0.38, 0.25, 0.18, 0.85))
		overlay.draw_circle(c1, 7.0, Color("e8e2d5"))
		overlay.draw_circle(c2, 7.0, Color("e8e2d5"))
	elif tool_key == "beam":
		# Highlight brass lens aperture ring & top ceramic insulators
		var lens_c := Vector2(172.0, 180.0)
		overlay.draw_arc(lens_c, 34.0, 0.0, TAU, 32, Color(0.78, 0.62, 0.28, 0.75), 5.0, true)
		overlay.draw_circle(lens_c, 22.0, Color(0.92, 0.86, 0.66, 0.65))
	elif tool_key == "clock":
		# Highlight front cassette window spools & brass side key lobes
		overlay.draw_rect(Rect2(Vector2(198.0, 160.0), Vector2(68.0, 44.0)), Color(0.05, 0.06, 0.08, 0.82))
		overlay.draw_circle(Vector2(216.0, 182.0), 8.0, Color("e8e2d5"))
		overlay.draw_circle(Vector2(248.0, 182.0), 8.0, Color("e8e2d5"))


func _draw_operation_layer(op: Dictionary, is_done: bool, is_active: bool) -> void:
	var kind: StringName = op["kind"]
	if kind == &"spin":
		_draw_spin_operation(op, is_done, is_active)
	elif kind == &"trace":
		_draw_trace_operation(op, is_done, is_active)
	elif kind == &"connect":
		_draw_connect_operation(op, is_done, is_active)


func _draw_spin_operation(op: Dictionary, is_done: bool, is_active: bool) -> void:
	var center: Vector2 = op["center"]
	var radius: float = float(op["radius"])
	var start_ang: float = float(op["start_angle"])
	var dir: float = float(op["dir"])
	var bpos: Vector2 = op.get("badge_pos", center + Vector2(-42.0, -radius - 24.0))
	if is_done:
		overlay.draw_arc(center, radius, 0.0, TAU, 32, GREEN, 3.5, true)
		_draw_badge(bpos, String(op["tag"]) + " ✓", GREEN)
		return
	if not is_active:
		overlay.draw_arc(center, radius, 0.0, TAU, 28, INK.darkened(0.55), 2.0, true)
		return

	# Active Spin ring
	var ring_col := RED if trace_bad else PURPLE
	overlay.draw_arc(center, radius, 0.0, TAU, 36, Color(0.18, 0.12, 0.28, 0.78), 12.0, true)
	overlay.draw_arc(center, radius, 0.0, TAU, 36, ring_col, 3.5, true)

	# Progress arc
	var prog_frac := clampf(spin_accum / maxf(0.01, spin_required), 0.0, 1.0)
	if prog_frac > 0.01:
		var use_dir := spin_locked_dir if spin_locked_dir != 0.0 else dir
		overlay.draw_arc(center, radius, start_ang, start_ang + use_dir * spin_required * prog_frac, 28, GREEN, 5.5, true)

	# Start handle & directional arrow head
	var start_pt := center + Vector2(cos(start_ang), sin(start_ang)) * radius
	overlay.draw_circle(start_pt, 9.0, GREEN if dragging else INK)
	overlay.draw_arc(start_pt, 9.0, 0.0, TAU, 16, ring_col, 2.0, true)

	var arrow_ang := start_ang + dir * PI * 1.15
	var arrow_tip := center + Vector2(cos(arrow_ang), sin(arrow_ang)) * radius
	var tang := Vector2(-sin(arrow_ang), cos(arrow_ang)) * dir
	var norm := Vector2(cos(arrow_ang), sin(arrow_ang))
	var tri := PackedVector2Array([
		arrow_tip + tang * 10.0,
		arrow_tip - tang * 6.0 + norm * 7.0,
		arrow_tip - tang * 6.0 - norm * 7.0,
	])
	overlay.draw_colored_polygon(tri, ring_col)
	_draw_badge(bpos, String(op["tag"]), ring_col)


func _draw_trace_operation(op: Dictionary, is_done: bool, is_active: bool) -> void:
	var full_pts: Array[Vector2] = []
	full_pts.assign(op["points"])
	var bpos: Vector2 = op.get("badge_pos", full_pts[0] + Vector2(-24.0, -28.0))
	if is_done:
		for i in range(full_pts.size() - 1):
			overlay.draw_line(full_pts[i], full_pts[i + 1], Color("1d3a34"), 10.0, true)
		overlay.draw_polyline(PackedVector2Array(full_pts), GREEN, 3.5, true)
		_draw_badge(bpos, String(op["tag"]) + " ✓", GREEN)
		return
	if not is_active:
		for i in range(full_pts.size() - 1):
			overlay.draw_dashed_line(full_pts[i], full_pts[i + 1], INK.darkened(0.45), 2.0, 6.0, true)
		overlay.draw_circle(full_pts[0], 7.0, INK.darkened(0.55))
		overlay.draw_circle(full_pts[-1], 7.0, INK.darkened(0.55))
		return

	# Already-intact prefix of this trace (when stage == 3 or local_intact > 0)
	if route.size() >= 2 and full_pts.size() >= 2 and route[0].distance_to(full_pts[0]) > 2.0:
		var intact_slice := _slice_polyline(full_pts, 0.0, 0.5)
		if intact_slice.size() >= 2:
			overlay.draw_polyline(PackedVector2Array(intact_slice), GREEN, 4.0, true)

	for i in range(route.size() - 1):
		overlay.draw_line(route[i], route[i + 1], Color(0.10, 0.24, 0.34, 0.85), CORRIDOR * 1.35, true)
		overlay.draw_dashed_line(route[i], route[i + 1], BLUE, 2.0, 7.0, true)
	if stroke.size() > 1:
		overlay.draw_polyline(PackedVector2Array(stroke), RED if trace_bad else GREEN, 4.0, true)
	for i in range(route.size()):
		var c_col := GREEN if (dragging and i < next_contact) else BLUE
		overlay.draw_circle(route[i], 13.0, c_col.darkened(0.68))
		overlay.draw_arc(route[i], 13.0, 0.0, TAU, 20, c_col, 2.5, true)
		overlay.draw_string(ThemeDB.fallback_font, route[i] + Vector2(-4.0, 5.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	_draw_badge(bpos, String(op["tag"]), BLUE)


func _draw_connect_operation(op: Dictionary, is_done: bool, is_active: bool) -> void:
	var pairs: Array = op["pairs"]
	var first_pos: Vector2 = pairs[0]["a"]
	var bpos: Vector2 = op.get("badge_pos", first_pos + Vector2(-20.0, -32.0))
	if is_done:
		for p in pairs:
			overlay.draw_line(p["a"], p["b"], GREEN, 3.5, true)
			_draw_terminal_node(p["a"], p["shape"], p["label"], GREEN, true)
			_draw_terminal_node(p["b"], p["shape"], p["label"], GREEN, true)
		_draw_badge(bpos, String(op["tag"]) + " ✓", GREEN)
		return
	if not is_active:
		for p in pairs:
			overlay.draw_dashed_line(p["a"], p["b"], INK.darkened(0.55), 1.5, 6.0, true)
			_draw_terminal_node(p["a"], p["shape"], p["label"], INK.darkened(0.45), false)
			_draw_terminal_node(p["b"], p["shape"], p["label"], INK.darkened(0.45), false)
		return

	# Active Connect operation
	for pair_idx in range(pairs.size()):
		var p: Dictionary = pairs[pair_idx]
		var pair_done := pair_idx in connected_pairs
		var col := GREEN if pair_done else YELLOW
		if pair_done:
			overlay.draw_line(p["a"], p["b"], GREEN, 4.0, true)
		else:
			overlay.draw_dashed_line(p["a"], p["b"], YELLOW.darkened(0.25), 2.0, 6.0, true)
		for side in ["a", "b"]:
			var is_sel: bool = (not selected_terminal.is_empty()) and int(selected_terminal["pair_index"]) == pair_idx and String(selected_terminal["side"]) == side
			var t_col := GREEN if (pair_done or is_sel) else (RED if trace_bad else col)
			_draw_terminal_node(p[side], p["shape"], p["label"], t_col, pair_done or is_sel)

	if stroke.size() > 1:
		overlay.draw_polyline(PackedVector2Array(stroke), RED if trace_bad else GREEN, 3.5, true)
	_draw_badge(bpos, String(op["tag"]), YELLOW)


func _draw_terminal_node(pos: Vector2, shape: StringName, label_txt: String, col: Color, filled: bool) -> void:
	overlay.draw_circle(pos, 15.0, col.darkened(0.72) if not filled else col.darkened(0.42))
	overlay.draw_arc(pos, 15.0, 0.0, TAU, 22, col, 2.5, true)
	# Distinct geometric symbol (▲ triangle vs ■ square) + explicit text label ("A" vs "B")
	if shape == &"triangle":
		var tri := PackedVector2Array([
			pos + Vector2(-4.0, -7.0),
			pos + Vector2(-10.0, 5.0),
			pos + Vector2(2.0, 5.0),
		])
		overlay.draw_colored_polygon(tri, col)
	else:
		overlay.draw_rect(Rect2(pos + Vector2(-10.0, -5.0), Vector2(10.0, 10.0)), col, true)
	overlay.draw_string(ThemeDB.fallback_font, pos + Vector2(3.0, 5.0), label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)


func _draw_badge(pos: Vector2, text: String, col: Color) -> void:
	var clamped := Vector2(clampf(pos.x, 8.0, BOARD.x - 148.0), clampf(pos.y, 26.0, BOARD.y - 22.0))
	var w := maxf(88.0, float(text.length()) * 7.2 + 14.0)
	var rect := Rect2(clamped, Vector2(w, 20.0))
	overlay.draw_rect(rect, Color(0.05, 0.08, 0.12, 0.88), true)
	overlay.draw_rect(rect, col, false, 1.5)
	overlay.draw_string(ThemeDB.fallback_font, clamped + Vector2(6.0, 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)


func _draw_operation_pills(ops: Array, full: bool) -> void:
	var pill_w := 160.0
	var gap := 10.0
	var start_x := (BOARD.x - (pill_w * 3.0 + gap * 2.0)) * 0.5
	for i in range(ops.size()):
		var op: Dictionary = ops[i]
		var is_done := full or (i < active_op_index)
		var is_act := (not full) and (i == active_op_index)
		var col := GREEN if is_done else (BLUE if is_act else INK.darkened(0.55))
		var rect := Rect2(Vector2(start_x + float(i) * (pill_w + gap), 4.0), Vector2(pill_w, 19.0))
		overlay.draw_rect(rect, Color(0.06, 0.09, 0.14, 0.90), true)
		overlay.draw_rect(rect, col, false, 2.0 if is_act else 1.0)
		var status_suffix := " ✓" if is_done else (" •" if is_act else "")
		var txt := "%d. %s%s" % [i + 1, String(op["short"]), status_suffix]
		overlay.draw_string(ThemeDB.fallback_font, rect.position + Vector2(7.0, 14.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK if (is_done or is_act) else INK.darkened(0.35))
