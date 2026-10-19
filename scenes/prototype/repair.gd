class_name WeaponRepair
extends Control

signal stage_changed(tool: StringName, stage: int)
signal tool_switched(tool: StringName)

const Gestures = preload("res://scenes/prototype/repair_gestures.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const ToolModels := {
	"ring": preload("res://assets/equipment/ring_caster.glb"),
	"beam": preload("res://assets/equipment/flash_camera.glb"),
	"cone": preload("res://assets/equipment/heat_bellows.glb"),
}

const BOARD := Vector2(520.0, 260.0)
const PANEL_MIN_SIZE := Vector2(280.0, 220.0)
const BOARD_MIN_SIZE := Vector2(240.0, 120.0)
const CORRIDOR := Gestures.TRACE_CORRIDOR
const CONTACT := Gestures.TRACE_CONTACT

const GUIDE := ToolStyle.REPAIR_GUIDE
const GUIDE_BRIGHT := Color("f8f3e8")
const GUIDE_MUTED := Color(0.898039, 0.870588, 0.815686, 0.56)
const GUIDE_TRACK := Color(0.898039, 0.870588, 0.815686, 0.22)
const RED := Color("ef8c94")
const DARK_BACKING := Color(0.018, 0.028, 0.044, 0.90)
const MODEL_TRANSLUCENCY_ALPHA := 0.84

const TOOL_ORDER: Array[StringName] = [&"ring", &"beam", &"cone"]
const COMPLETION_FLASH_DURATION_SEC := 0.36
const STAGE_HINT_MAX_PASSES := 2.0
const SPIN_COMPLETION_TOLERANCE := 0.12 # Seven degrees of release forgiveness.

var ROUTES: Array = []
var equipment: WeaponEquipment
var time_controller: TimeController = null
var tool: StringName = &"ring"
var _session: int = -1
var _arena_ref: Node = null
var _allow_full_preview := false

@onready var panel: PanelContainer = get_node_or_null("Panel") as PanelContainer
@onready var board: Control = get_node_or_null("Panel/Margin/Column/Board") as Control
@onready var overlay: Control = get_node_or_null("Panel/Margin/Column/Board/GestureOverlay") as Control
@onready var condition_slot: Control = get_node_or_null("Panel/Margin/Column/Board/ConditionSlot") as Control
@onready var viewport_container: SubViewportContainer = get_node_or_null("Panel/Margin/Column/Board/ToolBackdropViewport") as SubViewportContainer
@onready var sub_viewport: SubViewport = get_node_or_null("Panel/Margin/Column/Board/ToolBackdropViewport/SubViewport") as SubViewport
@onready var preview_cam: Camera3D = get_node_or_null("Panel/Margin/Column/Board/ToolBackdropViewport/SubViewport/PreviewCamera") as Camera3D
@onready var heading: Label = get_node_or_null("Panel/Margin/Column/HeaderRow/Heading") as Label
@onready var instructions: Label = get_node_or_null("Panel/Margin/Column/Instructions") as Label
@onready var progress: Label = get_node_or_null("Panel/Margin/Column/HeaderRow/Progress") as Label
@onready var feedback: Label = get_node_or_null("Panel/Margin/Column/Feedback") as Label
@onready var close_hint: Label = get_node_or_null("ExitControls/CloseHint") as Label
@onready var switch_hint: Label = get_node_or_null("ExitControls/SwitchHint") as Label
@onready var meter: ProgressBar = get_node_or_null("Panel/Margin/Column/Meter") as ProgressBar
@onready var carousel: RepairCarouselView = $Carousel

var condition_view: RepairConditionView = null
var model_instances: Dictionary = {}
var projected_operations: Array = []

var full_path: Array[Vector2] = []
var solved_path: Array[Vector2] = []
var missing_path: Array[Vector2] = []
var future_missing_path: Array[Vector2] = []
var route: Array[Vector2] = []
var stroke: Array[Vector2] = []

var _dragging := false
var dragging: bool:
	get:
		return _dragging
	set(value):
		_dragging = value
		if _dragging:
			_snap_switch_transition()
		_sync_gesture_active()

var next_contact := 1
var trace_stage := 0
var trace_bad := false
var active_op_index := 0

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
var _completed_spin_angle := 0.0

var connected_pairs: Array[int] = []
var selected_terminal: Dictionary = {}
var _drag_pair_pending: int = -1
var _drag_completed_pairs: Array[int] = []
var _overlays: Array[Node] = []
var preview_rect := Rect2()
var _model_region := Rect2()

var _completion_flash_op: Dictionary = {}
var _completion_flash_until_usec: int = 0
var _stage_hint_active := false
var _stage_hint_prompt := ""
var _stage_hint_phase := 0.0
var _stage_hint_passes := 0.0
var _learned_gestures: Dictionary = {}
var _switch_transition_alpha := 1.0
var _switch_transition_offset := Vector2.ZERO
var _last_emitted_tool: StringName = &""
var _last_emitted_stage: int = -99


func _init() -> void:
	_rebuild_routes_for_tool(tool)


func _rebuild_routes_for_tool(for_tool: StringName) -> void:
	# Freeze projected targets while a gesture is actively dragging so nothing drifts underneath the cursor.
	if _dragging and for_tool == tool and not projected_operations.is_empty():
		return
	var spec := Gestures.tool_spec(for_tool)
	var raw_ops: Array = spec["operations"]
	projected_operations.clear()
	var holder: Node3D = model_instances.get(String(for_tool)) if model_instances.has(String(for_tool)) else null
	var can_use_cam := preview_cam != null and preview_cam.is_inside_tree() and holder != null and holder.is_inside_tree()
	if can_use_cam:
		holder.position = spec["model_pos"]
		holder.rotation_degrees = spec["model_rot_deg"]
		preview_cam.position = spec["cam_pos"]
		preview_cam.size = float(spec["cam_size"])
		preview_cam.look_at_from_position(preview_cam.position, spec["cam_target"], Vector3.UP)
	for op in raw_ops:
		if can_use_cam:
			projected_operations.append(Gestures.project_operation_with_camera(op, holder, preview_cam))
		else:
			projected_operations.append((op as Dictionary).duplicate(true))

	ROUTES.clear()
	for stage_idx in range(4):
		var op_idx := Gestures.operation_index_for_stage(stage_idx)
		var op: Dictionary = projected_operations[clampi(op_idx, 0, projected_operations.size() - 1)]
		var kind: StringName = op["kind"]
		if kind == &"spin":
			ROUTES.append(Gestures.sample_spin_arc(op["center"], float(op["radius"]), float(op["start_angle"]), float(op["dir"]), Gestures.SPIN_FULL_RADIANS, 8))
		elif kind == &"trace":
			var pts: Array[Vector2] = []
			pts.assign(op["points"])
			if stage_idx == 3 and pts.size() >= 3:
				ROUTES.append(Gestures.slice_polyline(pts, 0.5, 1.0, CONTACT * 0.6))
			else:
				ROUTES.append(pts)
		elif kind == &"connect":
			var pairs: Array = op["pairs"]
			var cpts: Array[Vector2] = []
			if stage_idx == 3 and pairs.size() >= 2:
				cpts.append(pairs[1]["a"])
				cpts.append(pairs[1]["b"])
			else:
				for p in pairs:
					cpts.append(p["a"])
					cpts.append(p["b"])
			ROUTES.append(cpts)

	full_path.clear()
	for section_idx in range(ROUTES.size()):
		var section: Array = ROUTES[section_idx]
		for point_idx in range(section.size()):
			if section_idx > 0 and point_idx == 0 and not full_path.is_empty() and full_path[-1].distance_to(section[point_idx]) < 0.5:
				continue
			full_path.append(section[point_idx])


func _resolve_time_controller() -> TimeController:
	if is_instance_valid(time_controller):
		return time_controller
	var arena := _find_arena()
	if arena != null and "time_controller" in arena and arena.time_controller is TimeController:
		time_controller = arena.time_controller
		return time_controller
	return null


func _sync_gesture_active() -> void:
	var tc := _resolve_time_controller()
	if tc != null:
		tc.set_repair_gesture_active(_dragging and equipment != null and not equipment.is_full(tool))


func show_message(text: String) -> void:
	if feedback != null:
		feedback.text = text
	_queue_redraws()


func has_active_session(for_tool: StringName = &"") -> bool:
	if equipment == null or _session < 0:
		return false
	var target := tool if for_tool == &"" else for_tool
	return equipment.is_session_active(_session, target)


func current_stage(for_tool: StringName = &"") -> int:
	if equipment == null:
		return 0
	var target := tool if for_tool == &"" else for_tool
	return equipment.stage(target)


func current_operation_kind() -> StringName:
	return active_kind


func get_model_region() -> Rect2:
	if board == null:
		return Rect2(Vector2.ZERO, BOARD)
	if _dragging and _model_region.has_area():
		return _model_region
	var canvas := board.get_global_transform_with_canvas()
	var region := Rect2()
	var first := true
	var holder: Node3D = model_instances.get(String(tool))
	if holder != null and preview_cam != null:
		# Frame the visible item, not the empty corners of its wide viewport.
		for mesh: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree():
				continue
			var bounds := mesh.get_aabb()
			for i in range(8):
				var local := bounds.position + bounds.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)
				var pixel := preview_cam.unproject_position(mesh.global_transform * local)
				var point := canvas * (_board_offset() + pixel / Vector2(sub_viewport.size) * BOARD * _board_scale())
				region = Rect2(point, Vector2.ZERO) if first else region.expand(point)
				first = false
	if first:
		region = canvas * Rect2(_board_offset(), BOARD * _board_scale())
	_model_region = region.grow(24 * _board_scale())
	return _model_region


func show_stage_hint(custom_prompt: String = "") -> void:
	_stage_hint_active = true
	_stage_hint_prompt = custom_prompt
	_stage_hint_phase = 0.0
	_stage_hint_passes = 0.0
	if custom_prompt != "" and instructions != null:
		instructions.text = custom_prompt
	set_process(true)
	_queue_redraws()


func clear_stage_hint() -> void:
	_stage_hint_active = false
	_stage_hint_prompt = ""
	_stage_hint_phase = 0.0
	_stage_hint_passes = 0.0
	if is_node_ready():
		_refresh()
	_queue_redraws()


func _maybe_auto_show_spin_demo() -> void:
	if not is_inside_tree() or _allow_full_preview or equipment == null or equipment.is_full(tool):
		return
	if active_kind == &"spin" and not bool(_learned_gestures.get(&"spin", false)) and not _stage_hint_active:
		_stage_hint_active = true
		_stage_hint_phase = 0.0
		_stage_hint_passes = 0.0
		set_process(true)


func _emit_stage_if_changed() -> void:
	if equipment == null:
		return
	var s := equipment.stage(tool)
	if tool != _last_emitted_tool or s != _last_emitted_stage:
		_last_emitted_tool = tool
		_last_emitted_stage = s
		stage_changed.emit(tool, s)


func setup(params: Dictionary) -> void:
	equipment = params.get("equipment")
	if params.has("arena") and is_instance_valid(params["arena"]):
		_arena_ref = params["arena"]
	if params.get("time_controller") is TimeController:
		time_controller = params["time_controller"]
	else:
		_resolve_time_controller()
	_allow_full_preview = bool(params.get("allow_full_preview", false))
	if params.has("available_tools"):
		available_tools.clear()
		for item in params["available_tools"]:
			if item is int:
				var idx := int(item)
				if idx >= 1 and idx <= TOOL_ORDER.size():
					available_tools.append(TOOL_ORDER[idx - 1])
			else:
				var name_id := StringName(item)
				if name_id in TOOL_ORDER:
					available_tools.append(name_id)
	var requested_tool := StringName(params.get("tool", &"ring"))
	if not (requested_tool in TOOL_ORDER):
		requested_tool = &"ring"
	if _allow_full_preview:
		switch_tool(requested_tool)
		return
	var target_tool := Gestures.pick_repair_tool(equipment, _acquired_tools(), requested_tool)
	if target_tool != &"":
		var slot_idx := TOOL_ORDER.find(target_tool) + 1
		var arena := _find_arena()
		if arena != null and "weapons" in arena and arena.weapons != null and arena.weapons.selected_tool != slot_idx:
			arena.weapons.select_tool(slot_idx)
		switch_tool(target_tool)
	else:
		switch_tool(requested_tool)
		if is_node_ready():
			call_deferred("_request_close")


func switch_tool(next_tool: StringName) -> void:
	if not (next_tool in TOOL_ORDER):
		next_tool = &"ring"
	var changing_tool := (tool != next_tool)
	_clear_trace()
	_completion_flash_until_usec = 0
	if equipment != null and _session >= 0:
		equipment.end_repair(_session)
	tool = next_tool
	_completed_spin_angle = 0.0
	spin_visual_angle = 0.0
	_rebuild_routes_for_tool(tool)
	if equipment != null:
		if equipment.is_full(tool):
			_session = -1
		else:
			_session = equipment.begin_repair(tool)
	_sync_gesture_active()
	if changing_tool and is_node_ready():
		_start_switch_transition()
		tool_switched.emit(tool)
	if is_node_ready():
		_refresh()
		_maybe_auto_show_spin_demo()
		if equipment != null and equipment.is_full(tool):
			feedback.text = "Ready"
		else:
			feedback.text = ""
	_emit_stage_if_changed()


func _start_switch_transition() -> void:
	if _dragging:
		_snap_switch_transition()
		return
	_switch_transition_alpha = 0.55
	_switch_transition_offset = Vector2(12.0, 0.0)
	set_process(true)


func _snap_switch_transition() -> void:
	_switch_transition_alpha = 1.0
	_switch_transition_offset = Vector2.ZERO
	if viewport_container != null:
		viewport_container.modulate.a = 1.0
		viewport_container.position = _board_offset()


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
	if not available_tools.is_empty():
		return available_tools
	var arena := _find_arena()
	if arena != null and "weapons" in arena and arena.weapons != null and "available_tools" in arena.weapons:
		var out: Array[StringName] = []
		for idx in arena.weapons.available_tools:
			var i := int(idx)
			if i >= 1 and i <= TOOL_ORDER.size():
				out.append(TOOL_ORDER[i - 1])
		if not out.is_empty():
			return out
	var all_tools: Array[StringName] = []
	all_tools.assign(TOOL_ORDER)
	return all_tools


func _select_acquired_tool_index(index: int) -> bool:
	if index < 1 or index > TOOL_ORDER.size():
		return false
	var target_tool: StringName = TOOL_ORDER[index - 1]
	var acquired := _acquired_tools()
	if not (target_tool in acquired):
		show_message("That tool is not yet collected.")
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


func _ensure_condition_view() -> void:
	if is_instance_valid(carousel):
		condition_view = carousel.condition


func _sync_condition_view() -> void:
	_ensure_condition_view()
	if is_instance_valid(carousel):
		var slots: Array[int] = []
		for owned in _acquired_tools():
			slots.append(TOOL_ORDER.find(owned) + 1)
		carousel.bind_equipment(equipment, tool, slots)
		carousel.set_model_region(get_model_region())


func _on_carousel_selected(next_tool: StringName) -> void:
	_select_acquired_tool_index(TOOL_ORDER.find(next_tool) + 1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling is ColorRect:
				sibling.color = Color.TRANSPARENT
	if not board.resized.is_connected(_sync_tool_canvas):
		board.resized.connect(_sync_tool_canvas)
	if not board.gui_input.is_connected(_on_board_input):
		board.gui_input.connect(_on_board_input)
	if not overlay.draw.is_connected(_draw_overlay):
		overlay.draw.connect(_draw_overlay)
	_ensure_condition_view()
	carousel.tool_selected.connect(_on_carousel_selected)
	_populate_tool_models()
	if not resized.is_connected(_update_layout):
		resized.connect(_update_layout)
	if not get_viewport().size_changed.is_connected(_update_layout):
		get_viewport().size_changed.connect(_update_layout)
	var sm := _scene_manager()
	if sm != null and not sm.popup_opened.is_connected(_on_popup_opened):
		sm.popup_opened.connect(_on_popup_opened)
	_update_layout()
	_refresh()
	_maybe_auto_show_spin_demo()
	_emit_stage_if_changed()
	if not _allow_full_preview and equipment != null and Gestures.pick_repair_tool(equipment, _acquired_tools(), tool) == &"":
		call_deferred("_request_close")


func _process(delta: float) -> void:
	var keep_processing := false
	if _stage_hint_active and not _dragging and not bool(_learned_gestures.get(active_kind, false)) and _stage_hint_passes < STAGE_HINT_MAX_PASSES:
		var next_phase := _stage_hint_phase + delta * 0.78
		if next_phase >= 1.0:
			_stage_hint_passes += floorf(next_phase)
			_stage_hint_phase = fmod(next_phase, 1.0)
		else:
			_stage_hint_phase = next_phase
		if _stage_hint_passes < STAGE_HINT_MAX_PASSES:
			keep_processing = true
	if _completion_flash_until_usec > 0:
		if Time.get_ticks_usec() < _completion_flash_until_usec:
			keep_processing = true
		else:
			_completion_flash_until_usec = 0
			_completion_flash_op = {}
	if not _dragging and (_switch_transition_alpha < 0.999 or _switch_transition_offset.length() > 0.2):
		_switch_transition_alpha = move_toward(_switch_transition_alpha, 1.0, delta * 5.5)
		_switch_transition_offset = _switch_transition_offset.move_toward(Vector2.ZERO, delta * 130.0)
		if viewport_container != null:
			viewport_container.modulate.a = _switch_transition_alpha
			viewport_container.position = _board_offset() + _switch_transition_offset
		keep_processing = true
	_queue_redraws()
	if not keep_processing:
		set_process(false)


func _populate_tool_models() -> void:
	if sub_viewport == null:
		return
	for key in ToolModels.keys():
		if model_instances.has(key) and is_instance_valid(model_instances[key]):
			continue
		var holder := Node3D.new()
		holder.name = "Model_" + String(key)
		var inst: Node3D = ToolModels[key].instantiate()
		holder.add_child(inst)
		if key == "cone":
			_attach_heat_bellows_open_mechanisms(holder)
		_apply_instance_translucency(holder)
		holder.visible = false
		sub_viewport.add_child(holder)
		model_instances[key] = holder


# Applies mild per-instance translucency (depth pre-pass, no glow) without mutating shared GLB Mesh resources.
func _apply_instance_translucency(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is BaseMaterial3D:
			var dup_over := (mi.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
			_configure_translucent_material(dup_over)
			mi.material_override = dup_over
		elif mi.mesh != null:
			for s_idx in range(mi.mesh.get_surface_count()):
				var active_mat := mi.get_active_material(s_idx)
				if active_mat is BaseMaterial3D:
					var dup_mat := (active_mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					_configure_translucent_material(dup_mat)
					mi.set_surface_override_material(s_idx, dup_mat)
	for child in node.get_children():
		_apply_instance_translucency(child)


func _configure_translucent_material(mat: BaseMaterial3D) -> void:
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.albedo_color.a = clampf(mat.albedo_color.a * MODEL_TRANSLUCENCY_ALPHA, 0.72, MODEL_TRANSLUCENCY_ALPHA)
	mat.emission_enabled = false


func _attach_heat_bellows_open_mechanisms(holder: Node3D) -> void:
	if holder.find_child("Intake_Fan_Rotor", true, false) != null:
		return
	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color(0.84, 0.66, 0.34, 1.0)
	brass_mat.metallic = 0.65
	brass_mat.roughness = 0.32

	var slate_mat := StandardMaterial3D.new()
	slate_mat.albedo_color = Color(0.24, 0.28, 0.26, 1.0)
	slate_mat.roughness = 0.55

	var coil_mat := StandardMaterial3D.new()
	coil_mat.albedo_color = Color(0.94, 0.56, 0.32, 1.0)
	coil_mat.roughness = 0.38

	# Rear intake fan rotor inside open housing (+X camera-facing side under Y = -112 deg)
	var rotor := Node3D.new()
	rotor.name = "Intake_Fan_Rotor"
	rotor.position = Vector3(0.065, 0.188, 0.048)
	var hub := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.018
	cyl.height = 0.022
	hub.mesh = cyl
	hub.material_override = brass_mat
	rotor.add_child(hub)
	for i in range(4):
		var blade := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.088, 0.006, 0.018)
		blade.mesh = box
		blade.rotation.y = float(i) * PI * 0.25
		blade.material_override = brass_mat
		rotor.add_child(blade)
	holder.add_child(rotor)

	# Hinged open rear fan cover flap
	var cover := MeshInstance3D.new()
	cover.name = "Open_Fan_Cover"
	var cover_mesh := CylinderMesh.new()
	cover_mesh.top_radius = 0.052
	cover_mesh.bottom_radius = 0.052
	cover_mesh.height = 0.008
	cover.mesh = cover_mesh
	cover.position = Vector3(0.045, 0.238, 0.095)
	cover.rotation_degrees = Vector3(-68.0, 0.0, -12.0)
	cover.material_override = slate_mat
	holder.add_child(cover)

	# Hinged open front nozzle grille & exposed heating coil bars
	var grille := Node3D.new()
	grille.name = "Open_Front_Grille"
	grille.position = Vector3(0.088, 0.100, -0.485)
	for y_off in [0.052, -0.058]:
		var coil := MeshInstance3D.new()
		var cmesh := BoxMesh.new()
		cmesh.size = Vector3(0.016, 0.018, 0.110)
		coil.mesh = cmesh
		coil.position = Vector3(0.0, y_off, 0.0)
		coil.material_override = coil_mat
		grille.add_child(coil)
	holder.add_child(grille)


func _scene_manager() -> Node:
	return get_tree().root.get_node_or_null("SceneManager") if is_inside_tree() and get_tree() != null else null


func _update_3d_backdrop() -> void:
	if preview_cam == null:
		return
	var spec := Gestures.tool_spec(tool)
	var active_key := String(spec["id"])
	for key in model_instances.keys():
		var holder: Node3D = model_instances[key]
		holder.visible = (key == active_key)
		if holder.visible:
			if not _dragging:
				holder.position = spec["model_pos"]
				holder.rotation_degrees = spec["model_rot_deg"]
			_animate_model_parts(holder, spec)
	if not _dragging:
		preview_cam.position = spec["cam_pos"]
		preview_cam.size = float(spec["cam_size"])
		preview_cam.look_at_from_position(preview_cam.position, spec["cam_target"], Vector3.UP)


static func _rotate_node_around_pivot(node: Node3D, pivot: Vector3, axis: Vector3, angle: float) -> void:
	if node == null:
		return
	var norm_axis := axis.normalized() if axis.length() > 0.001 else Vector3.UP
	var rot_basis := Basis(norm_axis, angle)
	node.transform = Transform3D(rot_basis, pivot - rot_basis * pivot)


func _animate_model_parts(holder: Node3D, spec: Dictionary) -> void:
	var pivots: Dictionary = spec.get("spin_part_pivots", {})
	for node_name in pivots.keys():
		var part := holder.find_child(String(node_name), true, false) as Node3D
		if part == null:
			continue
		var info: Dictionary = pivots[node_name]
		var pivot: Vector3 = info.get("pivot", Vector3.ZERO)
		var axis: Vector3 = info.get("axis", Vector3.UP)
		var scale_factor: float = float(info.get("scale", 1.0))
		if String(node_name) == "Intake_Fan_Rotor":
			part.rotation.y = spin_visual_angle * scale_factor
		else:
			_rotate_node_around_pivot(part, pivot, axis, spin_visual_angle * scale_factor)


func _update_layout() -> void:
	if panel == null or _dragging:
		return
	if close_hint != null:
		close_hint.add_theme_font_size_override("font_size", 22 if size.y < 440 else 30)
	if switch_hint != null:
		switch_hint.add_theme_font_size_override("font_size", 12 if size.y < 440 else 13)
	if preview_rect.size.x > 0.0 and preview_rect.size.y > 0.0:
		panel.position = preview_rect.position
		panel.size = preview_rect.size
		_sync_tool_canvas()
		return
	var view_size := size if size.x > 0.0 and size.y > 0.0 else get_viewport_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		view_size = Vector2(960, 600)
	var edge := Vector2(clampf(view_size.x * 0.025, 12.0, 40.0), clampf(view_size.y * 0.035, 12.0, 34.0))
	var bottom_pad := clampf(view_size.y * 0.12, 76.0, 96.0)
	panel.position = edge
	panel.size = Vector2(view_size.x - edge.x * 2.0, view_size.y - edge.y - bottom_pad)
	_sync_tool_canvas()


func _style_prompt(label: Label, font_size: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", GUIDE)
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.025, 0.035, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y", 2)


func _sync_tool_canvas() -> void:
	if board == null or viewport_container == null or _dragging:
		return
	var b_offset := _board_offset()
	var b_scale := _board_scale()
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	viewport_container.position = b_offset + _switch_transition_offset
	viewport_container.size = BOARD * b_scale
	_sync_condition_view()
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
	if is_instance_valid(condition_view):
		condition_view.queue_redraw()


func _refresh() -> void:
	if board == null or equipment == null:
		return
	_update_3d_backdrop()
	if not _dragging:
		_rebuild_routes_for_tool(tool)
	_sync_condition_view()
	var spec := Gestures.tool_spec(tool)
	var cap: float = equipment.capacity(tool)
	var rem: float = equipment.remaining(tool)
	var cond: float = equipment.condition(tool)
	var full: bool = equipment.is_full(tool)
	heading.text = String(spec["title"])
	if full:
		active_op_index = 3
		active_op = projected_operations[2]
		active_kind = active_op["kind"]
		progress.text = "Ready"
		instructions.text = "Ready"
		solved_path.assign(full_path)
		missing_path.clear()
		future_missing_path.clear()
		route.assign(ROUTES[0])
	else:
		var s: int = equipment.stage(tool)
		var steps: int = equipment.repair_steps
		active_op_index = Gestures.operation_index_for_stage(s)
		active_op = projected_operations[clampi(active_op_index, 0, projected_operations.size() - 1)]
		active_kind = active_op["kind"]
		progress.text = "Step %d/3" % (active_op_index + 1)
		if _stage_hint_active and _stage_hint_prompt != "":
			instructions.text = _stage_hint_prompt
		else:
			instructions.text = String(active_op.get("prompt", "Complete the highlighted repair gesture."))
		solved_path = _slice_polyline(full_path, 0.0, cond)
		missing_path = _slice_polyline(full_path, cond, 1.0)
		var q_start := float(s) / float(steps)
		var q_end := float(s + 1) / float(steps)
		future_missing_path = _slice_polyline(full_path, q_end, 1.0)
		local_intact_ratio = clampf((cond - q_start) / maxf(0.0001, q_end - q_start), 0.0, 1.0)
		if not _dragging:
			_prepare_active_operation_geometry(s, local_intact_ratio)
		if active_kind == &"trace" and route.size() >= 2 and route.size() != 4 and not (_stage_hint_active and _stage_hint_prompt != ""):
			instructions.text = instructions.text.replace("1 to 4", "1 to %d" % route.size())
	meter.max_value = cap
	meter.value = rem
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
		route.assign(base_route)
	elif active_kind == &"connect":
		connected_pairs.clear()
		if stage_idx == 3:
			connected_pairs.append(0)
		elif local_intact >= 0.55 and active_op.get("pairs", []).size() >= 2:
			connected_pairs.append(0)
		route.assign(base_route)


func _input_available() -> bool:
	var sm := _scene_manager()
	var has_pause := bool(sm.has_popup(&"PauseMenu")) if sm != null else false
	var tc := _resolve_time_controller()
	var in_emergency := tc != null and (tc.emergency_active or tc.exhausted)
	return not is_queued_for_deletion() and not get_tree().paused and _overlays.is_empty() and not has_pause and not in_emergency


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
	spin_visual_angle = _completed_spin_angle + (spin_locked_dir if spin_locked_dir != 0.0 else 1.0) * spin_accum
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
		elif code >= KEY_1 and code <= KEY_3 and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			_select_acquired_tool_index(code - KEY_1 + 1)


func _request_close() -> void:
	_clear_trace()
	if equipment != null and _session >= 0:
		equipment.end_repair(_session)
		_session = -1
	var sm := _scene_manager()
	if sm != null and sm.has_popup(&"Repair"):
		sm.close_popup(&"Repair")
	elif not is_queued_for_deletion():
		queue_free()


func _board_scale() -> float:
	# Reserve space for side items and the outside condition arc. Keep the
	# selected model and all gesture targets on this one stable transform.
	var center := board.get_global_rect().get_center()
	var viewport_size := get_viewport_rect().size
	var radius_budget := maxf(40, minf(center.y, viewport_size.y - center.y) - 26)
	var arc_scale := radius_budget / (BOARD.length() * .5 + 24)
	return maxf(.01, minf(minf(board.size.x * .64 / BOARD.x, board.size.y / BOARD.y), arc_scale))


func _board_offset() -> Vector2:
	return (board.size - BOARD * _board_scale()) * 0.5


func _on_board_input(event: InputEvent) -> void:
	if not _can_trace():
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and equipment != null and equipment.is_full(tool):
			feedback.text = "Ready"
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
		if event.pressed and _dragging:
			var arena := _find_arena()
			if arena != null:
				arena.feedback.cue(StringName("repair_" + String(active_kind)), arena.player.global_position)
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
		feedback.text = ("Continue spinning (%d%%)." % pct) if pct > 0 else "Spin in either direction."
	elif dragging:
		_extend_spin(point)
		if dragging:
			if spin_accum >= spin_required - SPIN_COMPLETION_TOLERANCE:
				_commit_steps(1)
			else:
				if spin_stroke_accum >= 0.20 and not trace_bad:
					spin_base_accum = clampf(spin_accum, 0.0, spin_required)
				var pct := int(round(clampf(spin_accum / maxf(0.01, spin_required), 0.0, 1.0) * 100.0))
				_invalid("Released early (%d%% spun). Progress saved - drag again to finish." % pct if spin_base_accum > 0.01 else "Released early (%d%% spun). Completed checkpoints are safe; spin further." % pct)


func _extend_spin(finish: Vector2) -> void:
	var start := stroke[-1]
	if spin_accum >= spin_required - SPIN_COMPLETION_TOLERANCE:
		spin_accum = maxf(spin_accum, spin_required)
		spin_visual_angle = _completed_spin_angle + (spin_locked_dir if spin_locked_dir != 0.0 else 1.0) * spin_accum
		_update_3d_backdrop()
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
	if spin_accum >= spin_required * 0.35:
		_learned_gestures[&"spin"] = true
	# 1:1 angular correspondence between gesture rotation and 3D part rotation
	spin_visual_angle = _completed_spin_angle + (spin_locked_dir if spin_locked_dir != 0.0 else 1.0) * spin_accum
	_update_3d_backdrop()
	if stroke[-1].distance_to(finish) >= 3.0:
		stroke.append(finish)
	if spin_accum >= spin_required - SPIN_COMPLETION_TOLERANCE:
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
		feedback.text = "Trace in order and release at the end mark."
	elif dragging:
		_extend_trace(point)
		if dragging:
			if next_contact == route.size() and point.distance_to(route[-1]) <= CONTACT:
				var steps_to_award := 2 if (active_op_index == 2 and trace_stage == 2) else 1
				_commit_steps(steps_to_award)
			elif active_op_index == 2 and trace_stage == 2 and route.size() >= 3 and next_contact >= 3 and point.distance_to(route[2]) <= CONTACT:
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
			if next_contact >= 2:
				_learned_gestures[&"trace"] = true
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
	var added_indices: Array[int] = []
	for idx in pair_indices:
		if not (idx in connected_pairs):
			connected_pairs.append(idx)
			added_indices.append(idx)
	if added_indices.is_empty():
		return
	_learned_gestures[&"connect"] = true
	if active_op_index == 2:
		var committed := _commit_steps(added_indices.size())
		if committed < added_indices.size():
			for i in range(committed, added_indices.size()):
				connected_pairs.erase(added_indices[i])
			_queue_redraws()
	else:
		if connected_pairs.size() >= pairs.size():
			var committed := _commit_steps(1)
			if committed <= 0:
				for idx in added_indices:
					connected_pairs.erase(idx)
				_queue_redraws()
		else:
			var remaining_lbl := "square" if (0 in connected_pairs) else "triangle"
			feedback.text = "Pair connected! Now click the matching %s terminals." % remaining_lbl
			_queue_redraws()


func _invalid(message: String) -> void:
	dragging = false
	trace_bad = true
	feedback.text = message
	_queue_redraws()


func _commit_steps(step_count: int) -> int:
	if not _can_trace() or equipment.stage(tool) != trace_stage:
		_clear_trace()
		return 0
	var completed_op_snapshot := active_op.duplicate(true)
	var completed_kind := active_kind
	var tc := _resolve_time_controller()
	var total_restored := 0.0
	var committed_steps := 0
	var blocked_by_time := false
	for _i in range(maxi(1, step_count)):
		if equipment.is_full(tool):
			break
		if tc != null and not tc.try_spend_repair_checkpoint():
			blocked_by_time = true
			break
		var r: float = equipment.complete_step(tool, _session)
		if r <= 0.0:
			break
		total_restored += r
		committed_steps += 1
	if committed_steps <= 0 or total_restored <= 0.0:
		if blocked_by_time:
			if active_kind == &"spin" and spin_accum > 0.01:
				spin_base_accum = clampf(spin_accum, 0.0, spin_required)
				_clear_trace(true)
			else:
				_clear_trace()
			trace_bad = true
			feedback.text = "Not enough time for checkpoint - pause gesture to let time recharge."
			_queue_redraws()
		else:
			_clear_trace()
		return 0
	_learned_gestures[completed_kind] = true
	if completed_kind == &"spin":
		_completed_spin_angle += (spin_locked_dir if spin_locked_dir != 0.0 else 1.0) * maxf(spin_accum, spin_required)
	_completion_flash_op = completed_op_snapshot
	_completion_flash_until_usec = Time.get_ticks_usec() + int(COMPLETION_FLASH_DURATION_SEC * 1000000.0)
	set_process(true)
	_clear_trace()
	_refresh()
	_emit_stage_if_changed()
	if equipment.is_full(tool):
		equipment.end_repair(_session)
		_session = -1
		_sync_gesture_active()
		var next_damaged := Gestures.pick_repair_tool(equipment, _acquired_tools(), &"")
		if next_damaged != &"":
			var next_slot := TOOL_ORDER.find(next_damaged) + 1
			var arena := _find_arena()
			if arena != null and arena.has_method("_switch_tool") and next_slot >= 1:
				arena.call("_switch_tool", next_slot)
			switch_tool(next_damaged)
			var next_spec := Gestures.tool_spec(next_damaged)
			feedback.text = "Repair complete! Advanced to %s." % String(next_spec["title"])
			_queue_redraws()
		elif not _allow_full_preview:
			feedback.text = "All owned tools repaired!"
			_request_close()
		else:
			feedback.text = "Ready"
	elif blocked_by_time:
		feedback.text = "Checkpoint complete (+%.1f). Let time recharge for next checkpoint." % total_restored
	else:
		feedback.text = "Checkpoint complete (+%.1f) · Next step ready." % total_restored
	return committed_steps


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_trace()


func _exit_tree() -> void:
	dragging = false
	if equipment != null and _session >= 0:
		equipment.end_repair(_session)
		_session = -1


func _draw_overlay() -> void:
	if equipment == null:
		return
	overlay.draw_set_transform(_board_offset(), 0, Vector2.ONE * _board_scale())
	var full := equipment.is_full(tool)
	# Draw ONLY the current actionable repair UI. No future/completed operation badges or lines behind it.
	if not full:
		_draw_operation_layer(active_op, false, true)
		if _stage_hint_active and not _dragging and not bool(_learned_gestures.get(active_kind, false)) and _stage_hint_passes < STAGE_HINT_MAX_PASSES:
			_draw_stage_hint_overlay(active_op)
	else:
		_draw_badge(Vector2(214.0, 14.0), "READY ✓", GUIDE)

	if _completion_flash_until_usec > Time.get_ticks_usec() and not _completion_flash_op.is_empty():
		var rem_sec := float(_completion_flash_until_usec - Time.get_ticks_usec()) / 1000000.0
		var flash_t := clampf(rem_sec / COMPLETION_FLASH_DURATION_SEC, 0.0, 1.0)
		_draw_completion_flash(_completion_flash_op, flash_t)


func _draw_operation_layer(op: Dictionary, is_done: bool, is_active: bool) -> void:
	if not is_active and not is_done:
		return
	var kind: StringName = op["kind"]
	if kind == &"spin":
		_draw_spin_operation(op)
	elif kind == &"trace":
		_draw_trace_operation(op)
	elif kind == &"connect":
		_draw_connect_operation(op)


func _draw_spin_operation(op: Dictionary) -> void:
	var center: Vector2 = op["center"]
	var radius: float = float(op["radius"])
	var start_ang: float = float(op["start_angle"])
	var dir: float = float(op["dir"])
	var bpos: Vector2 = op.get("badge_pos", center + Vector2(-42.0, -radius - 28.0))

	var ring_col := RED if trace_bad else GUIDE
	overlay.draw_arc(center, radius, 0.0, TAU, 36, DARK_BACKING, 15.0, true)
	overlay.draw_arc(center, radius, 0.0, TAU, 36, GUIDE_TRACK, 7.0, true)
	overlay.draw_arc(center, radius, 0.0, TAU, 36, ring_col, 2.6, true)

	if local_intact_ratio > 0.02:
		var intact_end := start_ang + dir * Gestures.SPIN_FULL_RADIANS * minf(local_intact_ratio, 0.82)
		overlay.draw_arc(center, radius, start_ang, intact_end, 20, GUIDE_MUTED, 5.0, true)

	var prog_frac := clampf(spin_accum / maxf(0.01, spin_required), 0.0, 1.0)
	var base_ang := spin_grip_angle if (dragging or prog_frac > 0.01) else start_ang
	var use_dir := spin_locked_dir if spin_locked_dir != 0.0 else dir
	var head_ang := base_ang + use_dir * spin_required * prog_frac
	if prog_frac > 0.01:
		overlay.draw_arc(center, radius, base_ang, head_ang, 28, GUIDE_BRIGHT, 6.0, true)

	var handle_pt := center + Vector2(cos(head_ang), sin(head_ang)) * radius
	overlay.draw_circle(handle_pt, 10.0, DARK_BACKING)
	overlay.draw_circle(handle_pt, 8.0, GUIDE_BRIGHT if (dragging or prog_frac > 0.01) else GUIDE)
	overlay.draw_arc(handle_pt, 9.0, 0.0, TAU, 16, ring_col, 2.0, true)

	var dirs_to_draw: Array = [use_dir] if spin_locked_dir != 0.0 else [1.0, -1.0]
	for d_sign in dirs_to_draw:
		var arrow_ang := (head_ang if spin_locked_dir != 0.0 else base_ang) + float(d_sign) * PI * 0.55
		var arrow_tip := center + Vector2(cos(arrow_ang), sin(arrow_ang)) * radius
		var tang := Vector2(-sin(arrow_ang), cos(arrow_ang)) * float(d_sign)
		var norm := Vector2(cos(arrow_ang), sin(arrow_ang))
		var tri := PackedVector2Array([
			arrow_tip + tang * 10.0,
			arrow_tip - tang * 5.8 + norm * 6.4,
			arrow_tip - tang * 5.8 - norm * 6.4,
		])
		overlay.draw_colored_polygon(tri, GUIDE_BRIGHT if prog_frac >= 0.98 else ring_col)

	var tag_txt := String(op.get("tag", "SPIN"))
	if prog_frac > 0.01:
		tag_txt += " · %d%%" % int(round(prog_frac * 100.0))
	_draw_badge(bpos, tag_txt, ring_col)


func _draw_trace_operation(op: Dictionary) -> void:
	var full_pts: Array[Vector2] = []
	full_pts.assign(op["points"])
	var bpos: Vector2 = op.get("badge_pos", full_pts[0] + Vector2(-24.0, -28.0))

	if route.size() >= 2 and full_pts.size() >= 2 and route[0].distance_to(full_pts[0]) > 2.0:
		var intact_slice := _slice_polyline(full_pts, 0.0, 0.5)
		if intact_slice.size() >= 2:
			for i in range(intact_slice.size() - 1):
				overlay.draw_line(intact_slice[i], intact_slice[i + 1], DARK_BACKING, 11.0, true)
			overlay.draw_polyline(PackedVector2Array(intact_slice), GUIDE_MUTED, 4.0, true)

	var guide_col := RED if trace_bad else GUIDE
	for i in range(route.size() - 1):
		overlay.draw_line(route[i], route[i + 1], DARK_BACKING, CORRIDOR * 1.35, true)
		overlay.draw_line(route[i], route[i + 1], Color(0.16, 0.17, 0.19, 0.72), CORRIDOR * 1.05, true)
		overlay.draw_dashed_line(route[i], route[i + 1], guide_col, 2.4, 7.0, true)
	if stroke.size() > 1:
		overlay.draw_polyline(PackedVector2Array(stroke), RED if trace_bad else GUIDE_BRIGHT, 4.2, true)
	for i in range(route.size()):
		var reached := dragging and i < next_contact
		var c_col := GUIDE_BRIGHT if reached else guide_col
		overlay.draw_circle(route[i], 14.0, DARK_BACKING)
		overlay.draw_circle(route[i], 12.0, Color(0.18, 0.18, 0.20, 0.94) if not reached else Color(0.32, 0.30, 0.26, 0.94))
		overlay.draw_arc(route[i], 12.0, 0.0, TAU, 20, c_col, 2.4, true)
		overlay.draw_string(ThemeDB.fallback_font, route[i] + Vector2(-4.0, 5.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GUIDE_BRIGHT)

	_draw_badge(bpos, String(op.get("tag", "TRACE")), guide_col)


func _draw_connect_operation(op: Dictionary) -> void:
	var pairs: Array = op["pairs"]
	var first_pos: Vector2 = pairs[0]["a"]
	var bpos: Vector2 = op.get("badge_pos", first_pos + Vector2(-20.0, -32.0))

	for pair_idx in range(pairs.size()):
		var p: Dictionary = pairs[pair_idx]
		var pair_done := pair_idx in connected_pairs
		var pair_selected := not selected_terminal.is_empty() and int(selected_terminal["pair_index"]) == pair_idx
		var col := GUIDE_BRIGHT if pair_done else GUIDE
		overlay.draw_line(p["a"], p["b"], DARK_BACKING, 8.5, true)
		if pair_done:
			overlay.draw_line(p["a"], p["b"], GUIDE_BRIGHT, 3.8, true)
		else:
			overlay.draw_dashed_line(p["a"], p["b"], Color(col, 0.80 if pair_selected else 0.44), 2.0, 6.0, true)
		for side in ["a", "b"]:
			var is_sel: bool = pair_selected and String(selected_terminal["side"]) == side
			var t_col := GUIDE_BRIGHT if (pair_done or is_sel) else (RED if trace_bad else col)
			if pair_selected and not is_sel:
				overlay.draw_arc(p[side], 18.0, 0.0, TAU, 28, Color(GUIDE_BRIGHT, 0.85), 2.2, true)
			_draw_terminal_node(p[side], p["shape"], p["label"], t_col, pair_done or is_sel)

	if stroke.size() > 1:
		overlay.draw_polyline(PackedVector2Array(stroke), RED if trace_bad else GUIDE_BRIGHT, 3.8, true)

	_draw_badge(bpos, String(op.get("tag", "CONNECT")), RED if trace_bad else GUIDE)


func _draw_terminal_node(pos: Vector2, shape: StringName, _label_txt: String, col: Color, filled: bool) -> void:
	overlay.draw_circle(pos, 13.5, DARK_BACKING)
	overlay.draw_arc(pos, 12.2, 0.0, TAU, 24, col, 2.2, true)
	var points := PackedVector2Array()
	if shape == &"triangle":
		points = PackedVector2Array([pos + Vector2(0, -8.2), pos + Vector2(-7.2, 6.2), pos + Vector2(7.2, 6.2)])
	else:
		points = PackedVector2Array([pos + Vector2(-6.2, -6.2), pos + Vector2(6.2, -6.2), pos + Vector2(6.2, 6.2), pos + Vector2(-6.2, 6.2)])
	if filled:
		overlay.draw_colored_polygon(points, col)
	else:
		overlay.draw_colored_polygon(points, Color(col, 0.20))
	points.append(points[0])
	overlay.draw_polyline(points, col, 2.4, true)


func _draw_completion_flash(op: Dictionary, flash_t: float) -> void:
	var alpha := clampf(flash_t, 0.0, 1.0)
	var flash_col := Color(GUIDE_BRIGHT.r, GUIDE_BRIGHT.g, GUIDE_BRIGHT.b, alpha * 0.90)
	var kind := StringName(op.get("kind", &"spin"))
	var anchor := Vector2(BOARD.x * 0.5, BOARD.y * 0.5)
	if kind == &"spin":
		anchor = op.get("center", anchor)
	elif kind == &"connect":
		var pairs: Array = op.get("pairs", [])
		if not pairs.is_empty():
			anchor = Vector2(pairs[0]["a"]).lerp(Vector2(pairs[0]["b"]), 0.5)
	elif kind == &"trace":
		var pts: Array[Vector2] = []
		pts.assign(op.get("points", []))
		if not pts.is_empty():
			anchor = pts[pts.size() / 2]
	overlay.draw_circle(anchor, 11.0, Color(DARK_BACKING.r, DARK_BACKING.g, DARK_BACKING.b, alpha * 0.82))
	overlay.draw_arc(anchor, 11.0, 0.0, TAU, 20, flash_col, 1.8, true)
	overlay.draw_string(ThemeDB.fallback_font, anchor + Vector2(-5.0, 5.0), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, flash_col)


func _draw_stage_hint_overlay(op: Dictionary) -> void:
	var kind := StringName(op.get("kind", &"spin"))
	var hint_col := Color(GUIDE_BRIGHT.r, GUIDE_BRIGHT.g, GUIDE_BRIGHT.b, 0.90)
	var ghost_pos := Vector2.ZERO
	if kind == &"spin":
		var center: Vector2 = op["center"]
		var radius: float = float(op["radius"])
		var start_ang: float = float(op["start_angle"])
		var dir: float = float(op["dir"])
		var ang := start_ang + dir * Gestures.SPIN_FULL_RADIANS * _stage_hint_phase
		ghost_pos = center + Vector2(cos(ang), sin(ang)) * radius
		overlay.draw_arc(center, radius, start_ang, ang, 20, Color(hint_col, 0.55), 3.0, true)
	elif kind == &"connect":
		var pairs: Array = op.get("pairs", [])
		if not pairs.is_empty():
			var target_pair: Dictionary = pairs[1] if (0 in connected_pairs and pairs.size() >= 2) else pairs[0]
			ghost_pos = Vector2(target_pair["a"]).lerp(Vector2(target_pair["b"]), _stage_hint_phase)
			overlay.draw_dashed_line(target_pair["a"], ghost_pos, hint_col, 2.4, 5.0, true)
	elif kind == &"trace":
		if route.size() >= 2:
			var slice := _slice_polyline(route, 0.0, maxf(0.05, _stage_hint_phase))
			if not slice.is_empty():
				ghost_pos = slice[-1]
				if slice.size() >= 2:
					overlay.draw_polyline(PackedVector2Array(slice), Color(hint_col, 0.65), 3.0, true)
	if ghost_pos != Vector2.ZERO:
		overlay.draw_circle(ghost_pos, 8.5, Color(hint_col, 0.26))
		overlay.draw_arc(ghost_pos, 8.5, 0.0, TAU, 18, hint_col, 2.0, true)


# Small, subtle neutral verb/part label with no leader line crossing the puzzle.
func _draw_badge(pos: Vector2, text: String, col: Color) -> void:
	var w := maxf(72.0, float(text.length()) * 6.5 + 12.0)
	var clamped := Vector2(clampf(pos.x, 8.0, BOARD.x - w - 8.0), clampf(pos.y, 6.0, BOARD.y - 24.0))
	var rect := Rect2(clamped, Vector2(w, 18.0))
	overlay.draw_rect(rect, DARK_BACKING, true)
	overlay.draw_rect(rect, Color(col, 0.72), false, 1.2)
	overlay.draw_string(ThemeDB.fallback_font, clamped + Vector2(6.0, 13.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, GUIDE)
