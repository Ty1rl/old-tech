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
const PANEL_MIN_SIZE := Vector2(280.0, 220.0)
const BOARD_MIN_SIZE := Vector2(240.0, 120.0)
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
const TOOL_ORDER: Array[StringName] = [&"ring", &"beam", &"cone", &"clock"]

var active_op: Dictionary = {}
var active_kind: StringName = &"spin"
var local_intact_ratio := 0.0
var available_tools: Array[StringName] = []

var spin_accum := 0.0
var spin_base_accum := 0.0
var spin_stroke_accum := 0.0
var spin_stroke_dir := 0.0
var spin_required := Gestures.SPIN_FULL_RADIANS
var spin_locked_dir := 0.0
var spin_grip_angle := -PI * 0.5
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


var _arena_ref: Node = null


func setup(params: Dictionary) -> void:
	equipment = params.equipment
	if params.has("arena") and is_instance_valid(params["arena"]):
		_arena_ref = params["arena"]
	if params.has("available_tools"):
		available_tools.clear()
		for item in params["available_tools"]:
			if item is int:
				var idx := int(item)
				if idx >= 1 and idx <= TOOL_ORDER.size():
					available_tools.append(TOOL_ORDER[idx - 1])
			else:
				available_tools.append(StringName(item))
	switch_tool(StringName(params.get("tool", &"ring")))


func switch_tool(next_tool: StringName) -> void:
	_clear_trace()
	if equipment != null and _session >= 0:
		equipment.end_repair(_session)
	tool = next_tool
	_rebuild_routes_for_tool(tool)
	if equipment != null:
		if equipment.is_full(tool):
			_session = -1
		else:
			_session = equipment.begin_repair(tool)
	if is_node_ready():
		_refresh()
		if equipment != null and equipment.is_full(tool):
			feedback.text = "Ready · Tab / 1–4 switch tools · E or Esc close."
		else:
			feedback.text = "E or Esc close · Tab / 1–4 switch tools · WASD move · Space slow."


func _find_arena() -> Node:
	if is_instance_valid(_arena_ref):
		return _arena_ref
	if not is_inside_tree() or get_tree() == null:
		return null
	var scene := get_tree().current_scene
	if scene != null and "weapons" in scene and scene.weapons != null:
		return scene
	for child in get_tree().root.get_children():
		if "weapons" in child and child.weapons != null:
			return child
	return null


func _acquired_tools() -> Array[StringName]:
	var arena := _find_arena()
	if arena != null and "available_tools" in arena.weapons:
		var out: Array[StringName] = []
		for idx in arena.weapons.available_tools:
			var i := int(idx)
			if i >= 1 and i <= TOOL_ORDER.size():
				out.append(TOOL_ORDER[i - 1])
		return out
	if not available_tools.is_empty():
		return available_tools
	var all_tools: Array[StringName] = []
	all_tools.assign(TOOL_ORDER)
	return all_tools


func _select_acquired_tool_index(index: int) -> bool:
	if index < 1 or index > TOOL_ORDER.size():
		return false
	var target_tool: StringName = TOOL_ORDER[index - 1]
	var acquired := _acquired_tools()
	if not (target_tool in acquired):
		feedback.text = "That tool is not yet collected."
		_queue_redraws()
		return false
	var arena := _find_arena()
	if arena != null and arena.has_method("_switch_tool"):
		arena.call("_switch_tool", index)
	if tool != target_tool or (equipment != null and not equipment.is_full(target_tool) and not equipment.is_session_active(_session, target_tool)):
		switch_tool(target_tool)
	return true


func _cycle_acquired_tool(backward: bool = false) -> bool:
	var acquired := _acquired_tools()
	if acquired.is_empty():
		return false
	var current_idx := acquired.find(tool)
	if current_idx < 0:
		current_idx = 0
	var next_tool: StringName = acquired[posmod(current_idx + (-1 if backward else 1), acquired.size())]
	var slot_index := TOOL_ORDER.find(next_tool) + 1
	return _select_acquired_tool_index(slot_index)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling is ColorRect:
				sibling.color = Color.TRANSPARENT
	panel = PanelContainer.new()
	panel.custom_minimum_size = PANEL_MIN_SIZE
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	column.add_child(header_row)
	heading = Label.new()
	_style_prompt(heading, 22)
	header_row.add_child(heading)
	progress = Label.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_prompt(progress, 16)
	header_row.add_child(progress)
	meter = ProgressBar.new()
	meter.show_percentage = false
	meter.custom_minimum_size.y = 5
	column.add_child(meter)
	instructions = Label.new()
	instructions.text = "Spin, trace, or connect the highlighted mechanism."
	_style_prompt(instructions, 18)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.max_lines_visible = 2
	column.add_child(instructions)
	board = Control.new()
	board.custom_minimum_size = BOARD_MIN_SIZE
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.clip_contents = true
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.resized.connect(_sync_tool_canvas)
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
	if equipment != null and equipment.is_full(tool):
		feedback.text = "Ready · Tab / 1–4 switch tools · E or Esc close."
	else:
		feedback.text = "E or Esc close · Tab / 1–4 switch tools · WASD move · Space slow."
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.max_lines_visible = 2
	feedback.custom_minimum_size = Vector2(240, 20)
	_style_prompt(feedback, 15)
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
	# The tool floats over the live world. Only text gets a compact backing.
	var edge := Vector2(clampf(view_size.x * 0.025, 12.0, 40.0), clampf(view_size.y * 0.035, 12.0, 34.0))
	panel.position = edge
	panel.size = view_size - edge * 2.0
	_sync_tool_canvas()


func _style_prompt(label: Label, font_size: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.025, 0.035, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y", 2)


func _sync_tool_canvas() -> void:
	if board == null or viewport_container == null:
		return
	# Model projection, drawn targets and pointer input share one letterboxed canvas.
	# Stretching the model to the board independently moves targets off their parts.
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	viewport_container.position = _board_offset()
	viewport_container.size = BOARD * _board_scale()
	_queue_redraws()


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
		instructions.text = "All mechanisms aligned and ready. Tab / 1–4 switch tools · E or Esc close."
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
		progress.text = "Step %d/3 · %d / %d checkpoints · %.1f / %.1f" % [active_op_index + 1, s, steps, rem, cap]
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


func _clear_trace(preserve_spin: bool = false) -> void:
	dragging = false
	stroke.clear()
	next_contact = 1
	trace_bad = false
	spin_stroke_accum = 0.0
	spin_stroke_dir = 0.0
	if preserve_spin:
		spin_accum = spin_base_accum
	else:
		spin_accum = 0.0
		spin_base_accum = 0.0
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
			if event.pressed and not event.echo:
				_request_close()
		elif code == KEY_ESCAPE and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			_request_close()
		elif code == KEY_TAB and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			_cycle_acquired_tool(event.shift_pressed)
		elif code >= KEY_1 and code <= KEY_4 and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			_select_acquired_tool_index(code - KEY_1 + 1)


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
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and equipment != null and equipment.is_full(tool):
			feedback.text = "Ready · Tab / 1–4 switch tools · E or Esc close."
			_queue_redraws()
		else:
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
			if active_kind == &"spin" and spin_stroke_accum >= 0.20 and not trace_bad:
				spin_base_accum = clampf(spin_accum, 0.0, spin_required)
				_clear_trace(true)
			else:
				_clear_trace()
			feedback.text = "Mouse released; drag again to continue."
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
			feedback.text = "Grab the spin dial or drag around it. Nothing was lost."
			return
		var keep_bank := spin_base_accum > 0.01
		_clear_trace(keep_bank)
		dragging = true
		trace_stage = equipment.stage(tool)
		stroke = [point]
		var center: Vector2 = active_op["center"]
		if not keep_bank and point.distance_to(center) >= 4.0:
			spin_grip_angle = (point - center).angle()
		elif not keep_bank:
			spin_grip_angle = float(active_op.get("start_angle", -PI * 0.5))
		var pct := int(round(clampf(spin_accum / maxf(0.01, spin_required), 0.0, 1.0) * 100.0))
		feedback.text = ("Continue spinning (%d%%) in either direction." % pct) if pct > 0 else "Drag around the mechanism in either direction to spin."
	elif dragging:
		_extend_spin(point)
		if dragging:
			if spin_accum >= spin_required - 0.06:
				_commit_steps(1)
			else:
				if spin_stroke_accum >= 0.20 and not trace_bad:
					spin_base_accum = clampf(spin_accum, 0.0, spin_required)
				var pct := int(round(clampf(spin_accum / maxf(0.01, spin_required), 0.0, 1.0) * 100.0))
				_invalid("Released early (%d%% spun). Progress saved — drag again to finish." % pct if spin_base_accum > 0.01 else "Released early (%d%% spun). Completed checkpoints are safe; spin further." % pct)


func _extend_spin(finish: Vector2) -> void:
	var start := stroke[-1]
	if spin_accum >= spin_required - 0.06:
		# Target already reached during this drag: latch completion so wrist-stop hooks never lose it.
		spin_accum = maxf(spin_accum, spin_required)
		if stroke[-1].distance_to(finish) >= 3.0:
			stroke.append(finish)
		feedback.text = "Spin target reached (100%). Release to lock."
		return
	var prev_stroke_accum := spin_stroke_accum
	var res := Gestures.spin_step(active_op, start, finish, spin_stroke_accum, spin_stroke_dir)
	if not bool(res["ok"]):
		stroke.append(res["point"])
		var msg := String(res["message"])
		if msg.begins_with("Reversed"):
			spin_base_accum = 0.0
			spin_accum = 0.0
			spin_stroke_accum = 0.0
			spin_stroke_dir = 0.0
		elif spin_accum >= 0.25:
			spin_base_accum = clampf(spin_accum, 0.0, spin_required)
		_invalid(msg)
		return
	spin_stroke_accum = float(res["accum"])
	spin_stroke_dir = float(res["locked_dir"])
	if stroke.size() >= 2 and spin_stroke_dir != 0.0:
		var center: Vector2 = active_op["center"]
		var radius: float = float(active_op["radius"])
		if finish.distance_to(center) <= radius + Gestures.SPIN_ACTIVE_OUTER_PAD:
			var prev_vec := start - stroke[-2]
			var curr_vec := finish - start
			if prev_vec.length() >= 3.0 and curr_vec.length() >= 3.0:
				var turn_delta := wrapf(curr_vec.angle() - prev_vec.angle(), -PI, PI)
				if absf(turn_delta) < 1.25 and turn_delta * spin_stroke_dir > 0.02:
					var polar_gain := spin_stroke_accum - prev_stroke_accum
					var curve_gain := turn_delta * spin_stroke_dir * 0.85
					if curve_gain > polar_gain:
						spin_stroke_accum = prev_stroke_accum + curve_gain
	spin_accum = spin_base_accum + spin_stroke_accum
	if spin_stroke_dir != 0.0:
		spin_locked_dir = spin_stroke_dir
	spin_visual_angle = (spin_locked_dir if spin_locked_dir != 0.0 else 1.0) * spin_accum * 1.35
	_update_3d_backdrop()
	if stroke[-1].distance_to(finish) >= 3.0:
		stroke.append(finish)
	if spin_accum >= spin_required - 0.06:
		spin_accum = maxf(spin_accum, spin_required)
		feedback.text = "Spin target reached (100%). Release to lock."
	else:
		var pct := int(round(clampf(spin_accum / maxf(0.01, spin_required), 0.0, 1.0) * 100.0))
		var dir_txt := "CW" if spin_locked_dir >= 0.0 else "CCW"
		feedback.text = "Spinning %s · %d%%" % [dir_txt, pct]


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
				_invalid("Click an unconnected triangle or square socket. Nothing was lost.")
				return
			selected_terminal = term
			dragging = true
			_drag_pair_pending = -1
			_drag_completed_pairs.clear()
			stroke = [Vector2(term["position"])]
			feedback.text = "%s selected. Click or drag to the matching shape." % String(term["shape"]).capitalize()
		else:
			if term.is_empty() or int(term["pair_index"]) in connected_pairs:
				selected_terminal = {}
				_invalid("Missed matching terminal. Select a contact pair again.")
				return
			if int(term["pair_index"]) == int(selected_terminal["pair_index"]) and String(term["side"]) == String(selected_terminal["side"]):
				dragging = true
				stroke = [Vector2(term["position"])]
				feedback.text = "Click the other %s socket." % String(term["shape"])
				return
			if Gestures.terminals_match(selected_terminal, term):
				dragging = true
				_drag_pair_pending = int(term["pair_index"])
				stroke = [Vector2(selected_terminal["position"]), Vector2(term["position"])]
				feedback.text = "Matched %s sockets. Release to connect." % String(term["shape"])
			else:
				selected_terminal = {}
				_invalid("Shapes do not match. Join triangle to triangle or square to square.")
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
			feedback.text = "%s selected. Click the other matching shape." % String(selected_terminal["shape"]).capitalize()
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
			var remaining_lbl := "square" if (0 in connected_pairs) else "triangle"
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
		equipment.end_repair(_session)
		_session = -1
		feedback.text = "Ready. Repair complete · Tab / 1–4 switch tools · E or Esc close."
	else:
		feedback.text = "Checkpoint complete (+%.1f). Next operation ready · E or Esc close." % total_restored


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_trace()


func _exit_tree() -> void:
	if equipment != null:
		equipment.end_repair(_session)


func _draw_overlay() -> void:
	if equipment == null:
		return
	overlay.draw_set_transform(_board_offset(), 0, Vector2.ONE * _board_scale())
	if equipment.is_full(tool):
		var spec := Gestures.tool_spec(tool)
		_draw_badge(Vector2(18.0, 28.0), String(spec["title"]).to_upper() + " · READY ✓", GREEN)
		return
	# Completed and upcoming mechanisms stay unobscured; highlight only the live step.
	_draw_operation_layer(active_op, false, true)


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

	# Active Spin ring + subtle permissive grip zone halo
	var ring_col := RED if trace_bad else PURPLE
	overlay.draw_arc(center, radius + 16.0, 0.0, TAU, 36, Color(0.55, 0.42, 0.78, 0.16), 2.0, true)
	overlay.draw_arc(center, radius, 0.0, TAU, 36, Color(0.18, 0.12, 0.28, 0.78), 14.0, true)
	overlay.draw_arc(center, radius, 0.0, TAU, 36, ring_col, 3.5, true)

	# Progress arc from user's actual grip angle & direction
	var prog_frac := clampf(spin_accum / maxf(0.01, spin_required), 0.0, 1.0)
	var base_ang := spin_grip_angle if (dragging or prog_frac > 0.01) else start_ang
	var use_dir := spin_locked_dir if spin_locked_dir != 0.0 else dir
	var head_ang := base_ang + use_dir * spin_required * prog_frac
	if prog_frac > 0.01:
		overlay.draw_arc(center, radius, base_ang, head_ang, 28, GREEN, 6.0, true)

	# Live rotating handle dot
	var handle_pt := center + Vector2(cos(head_ang), sin(head_ang)) * radius
	overlay.draw_circle(handle_pt, 9.5, GREEN if (dragging or prog_frac > 0.01) else INK)
	overlay.draw_arc(handle_pt, 9.5, 0.0, TAU, 16, ring_col, 2.0, true)

	# Bidirectional arrows before direction lock; active direction arrow once turning
	var dirs_to_draw: Array = [use_dir] if spin_locked_dir != 0.0 else [1.0, -1.0]
	for d_sign in dirs_to_draw:
		var arrow_ang := (head_ang if spin_locked_dir != 0.0 else base_ang) + float(d_sign) * PI * 0.55
		var arrow_tip := center + Vector2(cos(arrow_ang), sin(arrow_ang)) * radius
		var tang := Vector2(-sin(arrow_ang), cos(arrow_ang)) * float(d_sign)
		var norm := Vector2(cos(arrow_ang), sin(arrow_ang))
		var tri := PackedVector2Array([
			arrow_tip + tang * 10.0,
			arrow_tip - tang * 6.0 + norm * 6.5,
			arrow_tip - tang * 6.0 - norm * 6.5,
		])
		overlay.draw_colored_polygon(tri, GREEN if prog_frac >= 0.98 else ring_col)

	var tag_txt := String(op["tag"])
	if prog_frac > 0.01:
		tag_txt += " · %d%%" % int(round(prog_frac * 100.0))
	_draw_badge(bpos, tag_txt, GREEN if prog_frac > 0.01 else ring_col)


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

	# Shape and color reinforce each pair. Selecting one quietly lights its mate.
	for pair_idx in range(pairs.size()):
		var p: Dictionary = pairs[pair_idx]
		var pair_done := pair_idx in connected_pairs
		var pair_selected := not selected_terminal.is_empty() and int(selected_terminal["pair_index"]) == pair_idx
		var pair_color := BLUE if p["shape"] == &"triangle" else YELLOW
		var col := GREEN if pair_done else pair_color
		if pair_done or pair_selected:
			overlay.draw_line(p["a"], p["b"], Color(col, 0.24), 7.0, true)
			overlay.draw_line(p["a"], p["b"], Color(col, 0.8), 1.5, true)
		for side in ["a", "b"]:
			var is_sel: bool = pair_selected and String(selected_terminal["side"]) == side
			var t_col := GREEN if (pair_done or is_sel) else (RED if trace_bad else col)
			if pair_selected and not is_sel:
				overlay.draw_arc(p[side], 19.0, 0.0, TAU, 28, Color(col, 0.72), 2.0, true)
			_draw_terminal_node(p[side], p["shape"], p["label"], t_col, pair_done or is_sel)

	if stroke.size() > 1:
		overlay.draw_polyline(PackedVector2Array(stroke), RED if trace_bad else GREEN, 3.5, true)


func _draw_terminal_node(pos: Vector2, shape: StringName, _label_txt: String, col: Color, filled: bool) -> void:
	overlay.draw_circle(pos, 12.0, Color(0.025, 0.035, 0.045, 0.88))
	overlay.draw_arc(pos, 12.0, 0.0, TAU, 24, col, 2.0, true)
	var points := PackedVector2Array()
	if shape == &"triangle":
		points = PackedVector2Array([pos + Vector2(0, -8), pos + Vector2(-7, 6), pos + Vector2(7, 6)])
	else:
		points = PackedVector2Array([pos + Vector2(-6, -6), pos + Vector2(6, -6), pos + Vector2(6, 6), pos + Vector2(-6, 6)])
	if filled:
		overlay.draw_colored_polygon(points, col)
	else:
		overlay.draw_colored_polygon(points, Color(col, 0.16))
	points.append(points[0])
	overlay.draw_polyline(points, col, 2.5, true)


func _draw_badge(pos: Vector2, text: String, col: Color) -> void:
	var clamped := Vector2(clampf(pos.x, 8.0, BOARD.x - 148.0), clampf(pos.y, 26.0, BOARD.y - 22.0))
	var w := maxf(88.0, float(text.length()) * 7.2 + 14.0)
	var rect := Rect2(clamped, Vector2(w, 20.0))
	overlay.draw_rect(rect, Color(0.05, 0.08, 0.12, 0.88), true)
	overlay.draw_rect(rect, col, false, 1.5)
	overlay.draw_string(ThemeDB.fallback_font, clamped + Vector2(6.0, 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
