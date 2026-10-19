class_name WeaponController
extends Node3D
## Equip/input coordinator. The three child scenes own their complete behaviors.
signal resolved_hit(tool: StringName, result: Dictionary, context: Dictionary, enemy_id: int)
signal combat_event(kind: StringName, point: Vector3, strength: float)
const TOOL_IDS: Array[StringName] = [&"ring", &"beam", &"cone"]
const CoverGeometry = preload("res://scenes/prototype/cover.gd")
@export var condition_settings: WeaponConditionSettings = preload("res://scenes/weapons/settings/weapon_condition.tres")
@export var time_controller: TimeController:
	set(value):
		if time_controller == value: return
		if is_instance_valid(time_controller):
			time_controller.emergency_started.disconnect(_on_emergency_started)
			time_controller.attempt_exhausted.disconnect(_on_attempt_exhausted)
		time_controller = value
		if is_instance_valid(value):
			value.emergency_started.connect(_on_emergency_started)
			value.attempt_exhausted.connect(_on_attempt_exhausted)
@onready var ring: RingCutter = $RingCutter
@onready var flash: FocusedFlash = $FocusedFlash
@onready var bellows: HeatBellows = $HeatBellows
@onready var presentation: WeaponPresentation = $Presentation
var equipment: WeaponEquipment:
	set(value):
		equipment = value
		if is_node_ready(): _bind_components()
var cover: CoverGeometry:
	set(value):
		cover = value
		if is_node_ready(): _bind_components()
var selected_tool := 1
var available_tools: Array[int] = [1, 2, 3]
var preview_overlay: Dictionary = {}
var mouse_held := false
var require_fresh_press := false
var last_aim := Vector3(0, 0, -6)
var last_feedback := "Ready"

func _ready() -> void:
	if equipment == null: equipment = WeaponEquipment.new(condition_settings)
	if cover == null: cover = CoverGeometry.new()
	_bind_components()
	if not _can_act(): cancel_input()

func _on_emergency_started(_charges: int) -> void:
	if is_node_ready(): cancel_input()

func _on_attempt_exhausted() -> void:
	if is_node_ready(): cancel_input()

func _bind_components() -> void:
	for component: WeaponComponent in [ring, flash, bellows]:
		component.bind(equipment, cover)
		if not component.resolved_hit.is_connected(_on_resolved_hit):
			component.resolved_hit.connect(_on_resolved_hit)
			component.combat_event.connect(_on_combat_event)
			component.feedback_changed.connect(_on_feedback)

func _on_resolved_hit(tool: StringName, result: Dictionary, context: Dictionary, enemy_id: int) -> void:
	resolved_hit.emit(tool, result, context, enemy_id)
func _on_combat_event(kind: StringName, point: Vector3, strength: float) -> void:
	combat_event.emit(kind, point, strength)
func _on_feedback(text: String) -> void:
	last_feedback = text

func set_loadout(tools: Array[int], preferred: int = 2) -> void:
	available_tools.clear()
	for tool in tools:
		if tool >= 1 and tool <= 3 and tool not in available_tools: available_tools.append(tool)
	if not is_node_ready():
		selected_tool = preferred if preferred in available_tools else (available_tools[0] if not available_tools.is_empty() else 1)
		return
	cancel_input()
	if not available_tools.is_empty(): select_tool(preferred if preferred in available_tools else available_tools[0])

func select_tool(index: int) -> void:
	if index not in available_tools or index < 1 or index > 3 or selected_tool == index: return
	if not is_node_ready():
		selected_tool = index
		return
	var held := mouse_held
	cancel_input()
	mouse_held = held
	require_fresh_press = held
	selected_tool = index
	last_feedback = "Switched to tool %d" % index

func _can_act() -> bool:
	return time_controller == null or (not time_controller.emergency_active and not time_controller.exhausted)

func handle_event(event: InputEvent, player: Node3D, aim: Vector3) -> void:
	last_aim = aim
	if not _can_act():
		cancel_input()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code in [KEY_1, KEY_2, KEY_3]: select_tool(code - KEY_1 + 1)
		return
	if player == null or available_tools.is_empty(): return
	var source := Vector3(player.global_position.x, 0, player.global_position.z)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_held = true
			require_fresh_press = false
			match selected_tool:
				1: ring.press(source, aim)
				2: flash.press()
				3: bellows.press(source, aim)
		else:
			var blocked := require_fresh_press
			mouse_held = false
			require_fresh_press = false
			if not blocked:
				match selected_tool:
					1: ring.release(source, aim, _muzzle(player, 1))
					2: flash.release(source, aim, _muzzle(player, 2))
					3: bellows.release()
	elif event is InputEventMouseMotion:
		if mouse_held and not require_fresh_press and selected_tool == 1: ring.sample(aim, source)
		if selected_tool == 3 and bellows.active: bellows.aim_at(source, aim)

func step(real_delta: float, player: Node3D, aim: Vector3, enemies: Array, world_delta: float = -1.0) -> void:
	last_aim = aim
	if not _can_act():
		cancel_input()
		return
	var dt := maxf(0, real_delta)
	var world := maxf(0, dt * (time_controller.world_scale if time_controller != null else 1.0) if world_delta < 0 else world_delta)
	var source := player.global_position if player != null else Vector3.ZERO
	presentation.phase = fposmod(presentation.phase + world, 1024)
	if player != null:
		if ring.drawing and not require_fresh_press: ring.sample(aim, source)
		if ring.flight_phase != "idle" and world > 0: ring.step(world, source, enemies)
		if bellows.active: bellows.aim_at(source, aim)
		bellows.step(dt, world, source, _muzzle(player, 3), enemies)
	flash.step(dt, world, enemies, _muzzle(player, 2))
	if player != null:
		var visual: Variant = player.get("visual")
		if is_instance_valid(visual) and visual.has_method("set_combat_pose"):
			visual.set_combat_pose(flash.flash_timer, bellows.active, flash.charge)
	rebuild_visuals(player)

func cancel_input() -> void:
	ring.cancel_input()
	flash.cancel_input()
	bellows.cancel_input()
	if mouse_held: require_fresh_press = true
	rebuild_visuals(null)

func reset_state() -> void:
	preview_overlay.clear()
	mouse_held = false
	require_fresh_press = false
	selected_tool = available_tools[0] if not available_tools.is_empty() else 1
	ring.reset_state()
	flash.reset_state()
	bellows.reset_state()
	presentation.reset()
	last_feedback = "Ready"

func capture_state() -> Dictionary:
	return {"ring": ring.capture_state(), "flash": flash.capture_state(), "bellows": bellows.capture_state(),
		"overlay": presentation_state().duplicate(true), "selected_tool": selected_tool,
		"phase": presentation.phase, "last_aim": last_aim, "last_feedback": last_feedback}

func restore_state(data: Dictionary) -> void:
	preview_overlay.clear()
	ring.restore_state(data.get("ring", {}))
	flash.restore_state(data.get("flash", {}))
	bellows.restore_state(data.get("bellows", {}))
	# Acquired tools are permanent progression, not replay state.
	var desired := int(data.get("selected_tool", selected_tool))
	if desired in available_tools: selected_tool = desired
	require_fresh_press = true
	presentation.phase = float(data.get("phase", 0))
	last_aim = data.get("last_aim", Vector3(0, 0, -6))
	last_feedback = String(data.get("last_feedback", "Ready"))
	rebuild_visuals(null)

func presentation_state() -> Dictionary:
	if not preview_overlay.is_empty(): return preview_overlay
	return {"tool": selected_tool, "charging": flash.charging, "charge": flash.charge,
		"ready": flash.charging and flash.charge >= flash.settings.pierce_threshold,
		"air": bellows.active, "phase": presentation.phase}

func rebuild_visuals(player: Node3D) -> void:
	ring.rebuild(player.global_position if player != null else Vector3.ZERO, player != null)
	var view := Basis.IDENTITY
	if player != null:
		var camera: Variant = player.get("camera")
		if camera is Camera3D: view = camera.global_basis
	presentation.rebuild(flash, bellows, presentation_state(), player.global_position if player != null else Vector3.ZERO, _muzzle(player, 2), _muzzle(player, 3), view)

func _muzzle(player: Node3D, index: int) -> Vector3:
	if player == null: return Vector3.ZERO
	# One visual adapter at the player boundary; components receive concrete points.
	var visual: Variant = player.get("visual")
	if is_instance_valid(visual) and visual.has_method("muzzle_position"): return visual.muzzle_position(index)
	return player.global_position + Vector3.UP * .8

func status_text() -> String:
	return "Tool %d · cutter %s · flash %.0f%% · bellows %s\n%s" % [selected_tool, ring.flight_phase, flash.charge * 100, "active" if bellows.active else "idle", last_feedback]
