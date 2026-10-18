class_name CombatArena
extends Node3D

const CreatureVisual = preload("res://scenes/prototype/creature_visual.gd")
const MuseumEnvironment = preload("res://scenes/prototype/museum_environment.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")
const PlayerScene = preload("res://scenes/prototype/combat_player.tscn")
const WeaponsScene = preload("res://scenes/weapons/weapons.tscn")
const EmergencyViewScene = preload("res://scenes/ui/emergency_view.tscn")
const Enemies = preload("res://scenes/prototype/enemies.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
const CombatFeedback = preload("res://scenes/prototype/combat_feedback.gd")
const TimeCue = preload("res://scenes/prototype/time_cue.gd")
const AimAssist = preload("res://scenes/prototype/aim_assist.gd")
const ScrubView = preload("res://scenes/prototype/scrub_view.gd")
const TimeCoreScene = preload("res://scenes/time/time_core.tscn")
const RepairGestures = preload("res://scenes/prototype/repair_gestures.gd")

const TOOL_IDS: Array[StringName] = [&"ring", &"beam", &"cone"]
## Held slow action, authored in project.godot (physical Space by default).
const SLOW_ACTION: StringName = &"slow_time"

var museum: Node3D
var equipment: WeaponEquipment
var cover: RefCounted = Cover.new()

var time_controller: TimeController
var emergency_rewind: EmergencyRewind
var history: ReplayHistory

var player: CombatPlayer
var weapons: WeaponController
var director: Node3D
var hud: Label
var slow_bar: ProgressBar
var status_hud: TimeStatusHUD
var emergency_view: EmergencyRewindView
var aim: Vector3 = Vector3.ZERO
var aim_valid: bool = false
## Camera distance scale in Tuning.VIEW.camera_size units (22 = authored framing).
## The authored Camera3D in combat_player.tscn keeps its inspector settings; zoom
## only scales its offset from the player.
var zoom: float = float(Tuning.VIEW.camera_size)
## Last slow_time press/release seen by _input. OR-ed with the native action state;
## cleared on every pause/state/focus change so a missed release cannot stick.
var _space_action_held := false
var _camera_rest_position := Vector3.ZERO
var _repair_held := false
var _suppress_next_lmb_release := false
var _last_emergency_age := 0.0
var time_feedback := ""
var time_cue: CanvasLayer
var feedback: Node3D
var scrub_view: RefCounted = ScrubView.new()
var _scrub_speed := 0.0


func _ready() -> void:
	_setup_time_core()
	_build_floor()
	_build_cover()
	museum = create_museum()
	museum.name = "MuseumEnvironment"
	museum.build()
	museum.apply_to_arena(self)
	player = PlayerScene.instantiate()
	player.time_controller = time_controller
	add_child(player)
	_camera_rest_position = player.camera.position
	weapons = WeaponsScene.instantiate()
	equipment = WeaponEquipment.new(weapons.condition_settings)
	weapons.equipment = equipment
	weapons.cover = cover
	weapons.time_controller = time_controller
	add_child(weapons)
	director = Enemies.new()
	director.cover = cover
	add_child(director)
	feedback = CombatFeedback.new()
	add_child(feedback)
	weapons.combat_event.connect(feedback.cue)
	weapons.resolved_hit.connect(_on_weapon_resolved_hit)
	director.enemy_event.connect(feedback.enemy_cue)
	feedback.set_music_playing(true)
	equipment.repaired.connect(_on_repaired)
	player.wounded.connect(_on_player_wounded)
	_build_hud()
	time_cue = TimeCue.new()
	add_child(time_cue)
	GameState.state_changed.connect(_on_state_changed)
	SceneManager.popup_opened.connect(_on_popup_opened)
	SceneManager.popup_closed.connect(_on_popup_closed)
	GameState.start_game()
	reset_arena()
	CreatureVisual.warmup(self)


func _exit_tree() -> void:
	if is_instance_valid(emergency_view):
		emergency_view.bind_emergency_rewind(null)


func _setup_time_core() -> void:
	var time_core: Node = TimeCoreScene.instantiate()
	add_child(time_core)
	time_controller = time_core.get_node("TimeController") as TimeController
	emergency_rewind = time_core.get_node("EmergencyRewind") as EmergencyRewind
	time_controller.auto_advance = false
	time_controller.set_physics_process(false)
	history = ReplayHistory.from_settings(time_controller.settings)
	emergency_rewind.time_controller = time_controller
	emergency_rewind.history = history
	emergency_rewind.capture_present = capture_state
	GameState.bind_emergency(emergency_rewind)
	emergency_rewind.started.connect(_on_emergency_started)
	emergency_rewind.selection_changed.connect(_on_emergency_selection_changed)
	emergency_rewind.confirmed.connect(_on_emergency_confirmed)
	emergency_rewind.ended.connect(_on_emergency_ended)
	time_controller.attempt_exhausted.connect(_on_attempt_exhausted)


func create_museum() -> Node3D:
	return MuseumEnvironment.new()


func _set_zoom(value: float) -> void:
	zoom = clampf(value, 10.0, 32.0)
	player.camera.position = _camera_rest_position * (zoom / float(Tuning.VIEW.camera_size))


func _active_repair_panel() -> WeaponRepair:
	return SceneManager.get_popup(&"Repair") as WeaponRepair


func _has_non_repair_popup() -> bool:
	for key in [&"PauseMenu", &"Developer", &"Settings", &"RunResult"]:
		if SceneManager.has_popup(key):
			return true
	return false


func _is_slow_held() -> bool:
	if _has_non_repair_popup() or GameState.is_paused():
		return false
	return _space_action_held or Input.is_action_pressed(SLOW_ACTION)


func _player_can_act() -> bool:
	return player.can_act


func _owned_tool_slots() -> Array[int]:
	return weapons.available_tools


func _owned_tool_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for slot in _owned_tool_slots():
		names.append(TOOL_IDS[slot - 1])
	return names


func _equipped_tool_name() -> StringName:
	if weapons == null:
		return &"ring"
	var idx := clampi(int(weapons.selected_tool), 1, TOOL_IDS.size())
	return TOOL_IDS[idx - 1]


func _switch_tool(index: int) -> void:
	if index < 1 or index > TOOL_IDS.size():
		return
	var repair_panel := _active_repair_panel()
	var owned_slots := _owned_tool_slots()
	if index not in owned_slots:
		if repair_panel != null:
			repair_panel.show_message("That tool is not yet collected.")
		return
	var target_tool: StringName = TOOL_IDS[index - 1]
	if index == weapons.selected_tool and (repair_panel == null or repair_panel.tool == target_tool):
		return
	weapons.select_tool(index)
	if repair_panel != null:
		if repair_panel.tool != target_tool or (not equipment.is_full(target_tool) and not repair_panel.has_active_session(target_tool)):
			repair_panel.switch_tool(target_tool)
	if time_controller != null:
		time_controller.slow_requested = _is_slow_held()
	_update_hud()


func _cycle_tool(backward: bool = false) -> void:
	var tools := _owned_tool_slots()
	if tools.is_empty():
		return
	var current := tools.find(weapons.selected_tool)
	if current < 0:
		current = 0
	_switch_tool(tools[posmod(current + (-1 if backward else 1), tools.size())])


func _open_smart_repair() -> bool:
	var owned_names := _owned_tool_names()
	if owned_names.is_empty():
		return false
	var target_tool := RepairGestures.pick_repair_tool(equipment, owned_names, _equipped_tool_name())
	if target_tool == &"":
		time_feedback = "All tools ready"
		_update_hud()
		return false
	var target_slot := TOOL_IDS.find(target_tool) + 1
	if target_slot >= 1 and weapons.selected_tool != target_slot:
		weapons.select_tool(target_slot)
	_repair_held = true
	SceneManager.push_popup(&"Repair", {
		"equipment": equipment,
		"tool": target_tool,
		"arena": self,
		"time_controller": time_controller,
	})
	_update_hud()
	return true


func _build_cover() -> void:
	for rectangle in cover.rectangles:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(rectangle.size.x, 2.2, rectangle.size.y)
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var geometry := BoxMesh.new()
		geometry.size = box.size
		mesh.mesh = geometry
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("65717a")
		mesh.material_override = material
		body.add_child(mesh)
		body.position = Vector3(rectangle.get_center().x, 1.1, rectangle.get_center().y)
		add_child(body)


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(Tuning.ARENA_HALF_SIZE * 2, 1, Tuning.ARENA_HALF_SIZE * 2)
	collision.shape = box
	floor_body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = box.size
	mesh.mesh = floor_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("303943")
	mesh.material_override = material
	floor_body.add_child(mesh)
	floor_body.position.y = -0.5
	add_child(floor_body)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -30, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("181d25")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 17)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	slow_bar = ProgressBar.new()
	slow_bar.position = Vector2(16, 130)
	slow_bar.size = Vector2(240, 16)
	slow_bar.max_value = time_controller.capacity if time_controller != null else 100.0
	slow_bar.show_percentage = false
	slow_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(slow_bar)
	status_hud = TimeStatusHUD.new()
	layer.add_child(status_hud)
	status_hud.bind_time_controller(time_controller)
	var emergency_layer := CanvasLayer.new()
	emergency_layer.layer = 60
	add_child(emergency_layer)
	emergency_view = EmergencyViewScene.instantiate()
	emergency_layer.add_child(emergency_view)
	emergency_view.bind_emergency_rewind(emergency_rewind)


func floor_aim(screen_position: Vector2) -> Vector3:
	var camera: Camera3D = player.camera
	var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(
		camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	aim_valid = hit != null
	if not aim_valid:
		return aim
	if is_instance_valid(director) and is_instance_valid(weapons):
		var target: Variant = AimAssist.target(screen_position, camera, director.enemies, weapons.selected_tool, player.global_position)
		if target != null:
			return target
	return hit


func _process(delta: float) -> void:
	if emergency_rewind != null and emergency_rewind.active:
		scrub_view.step(delta)
	_scrub_speed *= exp(-maxf(delta, 0.0) * 8.0)


func _step_player(delta: float) -> void:
	player.step(delta, aim)


func _physics_process(delta: float) -> void:
	if SceneManager.has_popup(&"Developer") or SceneManager.has_popup(&"Settings"):
		return
	time_controller.slow_requested = _is_slow_held()
	time_controller.advance(delta)
	if emergency_rewind.active or time_controller.emergency_active:
		feedback.step(delta, 0.0, 0.0, true, _scrub_speed, weapons, equipment)
		_update_hud()
		return
	if not _player_can_act():
		if SceneManager.has_popup(&"Repair"):
			_close_repair()
		feedback.step(delta, 0.0, 1.0, false, 0.0, weapons, equipment)
		_update_hud()
		return
	aim = floor_aim(get_viewport().get_mouse_position())
	_step_player(delta)
	player.position.x = clampf(player.position.x, -19.0, 19.0)
	player.position.z = clampf(player.position.z, -19.0, 19.0)
	var world_scale: float = time_controller.world_scale
	var world_delta: float = delta * world_scale
	director.step(world_delta, player)
	if (emergency_rewind.active or time_controller.emergency_active or not _player_can_act()) and SceneManager.has_popup(&"Repair"):
		_close_repair()
	if emergency_rewind.active or time_controller.emergency_active:
		feedback.step(delta, 0.0, 0.0, true, _scrub_speed, weapons, equipment)
		_update_hud()
		return
	weapons.step(delta, player, aim, director.enemies, world_delta)
	feedback.step(delta, world_delta, world_scale, false, 0.0, weapons, equipment)
	history.record(world_delta, capture_state)
	_update_hud()


# Handle emergency rewind, slow-time action, and mode exits before popup controls or weapon input can consume them.
func _input(event: InputEvent) -> void:
	if event.is_action(SLOW_ACTION):
		if not event.is_echo():
			_space_action_held = event.is_pressed()
			if time_controller != null:
				time_controller.slow_requested = _is_slow_held()
		get_viewport().set_input_as_handled()
		return

	if _suppress_next_lmb_release and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_suppress_next_lmb_release = false
		get_viewport().set_input_as_handled()
		return

	if emergency_rewind != null and emergency_rewind.active and not GameState.is_paused() and not _has_non_repair_popup():
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				emergency_rewind.step_selection(1)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				emergency_rewind.step_selection(-1)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_LEFT:
				_suppress_next_lmb_release = true
				emergency_rewind.confirm()
				get_viewport().set_input_as_handled()
				return
		elif event is InputEventKey and event.pressed and not event.echo:
			var key_code: int = event.physical_keycode if event.physical_keycode else event.keycode
			if key_code == KEY_ENTER or key_code == KEY_KP_ENTER:
				emergency_rewind.confirm()
				get_viewport().set_input_as_handled()
				return
			elif key_code == KEY_UP or key_code == KEY_LEFT:
				emergency_rewind.step_selection(1)
				get_viewport().set_input_as_handled()
				return
			elif key_code == KEY_DOWN or key_code == KEY_RIGHT:
				emergency_rewind.step_selection(-1)
				get_viewport().set_input_as_handled()
				return
		if event is InputEventMouse:
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if code == KEY_E:
			if not event.pressed:
				_repair_held = false
				if SceneManager.has_popup(&"Repair"):
					get_viewport().set_input_as_handled()
					return
			elif not event.echo and SceneManager.has_popup(&"Repair") and not _has_non_repair_popup():
				_repair_held = false
				_close_repair()
				get_viewport().set_input_as_handled()
				return
		if code == KEY_F10 and event.pressed and not event.echo and SceneManager.developer_tools:
			if SceneManager.has_popup(&"Developer"):
				SceneManager.close_popup(&"Developer")
			else:
				SceneManager.push_popup(&"Developer")
			get_viewport().set_input_as_handled()
			return
		if code == KEY_M and event.pressed and not event.echo:
			feedback.toggle_mute()
			_update_hud()
			get_viewport().set_input_as_handled()
			return
		if code == KEY_F7 and event.pressed and not event.echo:
			status_hud.cycle_readout()
			_update_hud()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and not _has_non_repair_popup() and (emergency_rewind == null or not emergency_rewind.active):
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if code == KEY_TAB or (code >= KEY_1 and code <= KEY_3):
			if code == KEY_TAB:
				_cycle_tool(event.shift_pressed)
			else:
				_switch_tool(code - KEY_1 + 1)
			get_viewport().set_input_as_handled()
			return
		if code == KEY_4:
			get_viewport().set_input_as_handled()
			return


func _unhandled_input(event: InputEvent) -> void:
	if emergency_rewind != null and emergency_rewind.active:
		return
	if SceneManager.has_popup():
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
			reset_arena()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if code == KEY_TAB:
			_cycle_tool(event.shift_pressed)
			return
		if code >= KEY_1 and code <= KEY_3:
			_switch_tool(code - KEY_1 + 1)
			return
		if code == KEY_4:
			return
		match code:
			KEY_EQUAL, KEY_PLUS:
				_set_zoom(zoom - 2.0)
				return
			KEY_MINUS:
				_set_zoom(zoom + 2.0)
				return
			KEY_F7:
				status_hud.cycle_readout()
				_update_hud()
				return
			KEY_E:
				if _player_can_act() and not _owned_tool_slots().is_empty():
					_open_smart_repair()
				return
			KEY_R:
				reset_arena()
				return
			KEY_BACKSPACE:
				director.clear()
				history.clear()
				history.seed_checkpoint(capture_state())
				return
			KEY_F1, KEY_F2, KEY_F3, KEY_F4:
				var kinds := [&"target", &"blue", &"yellow", &"orange"]
				director.spawn(kinds[code - KEY_F1], _spawn_position())
				history.clear()
				history.seed_checkpoint(capture_state())
				return
			KEY_F5:
				director.spawn_group()
				history.clear()
				history.seed_checkpoint(capture_state())
				return
			KEY_F8:
				director.spawn(&"side_guard", _spawn_position())
				history.clear()
				history.seed_checkpoint(capture_state())
				return
			KEY_F9:
				reset_arena()
				director.clear()
				_set_zoom(float(Tuning.VIEW.showcase_size))
				director.spawn(&"front_guard", Vector3(0, 0, -7))
				history.clear()
				history.seed_checkpoint(capture_state())
				_update_hud()
				return
			KEY_F6:
				reset_arena()
				director.start_encounter()
				history.clear()
				history.seed_checkpoint(capture_state())
				return
	aim = floor_aim(get_viewport().get_mouse_position())
	if aim_valid and _player_can_act():
		weapons.handle_event(event, player, aim)


func _spawn_position() -> Vector3:
	return Vector3(clampf(aim.x, -17, 17), 0, clampf(aim.z, -17, 17))


func reset_arena() -> void:
	if emergency_rewind != null and emergency_rewind.active:
		emergency_rewind.abandon()
	_close_repair()
	scrub_view.finish()
	feedback.reset_state()
	_repair_held = false
	_suppress_next_lmb_release = false
	_last_emergency_age = 0.0
	_space_action_held = Input.is_action_pressed(SLOW_ACTION)
	if time_controller != null:
		time_controller.begin_attempt()
		time_controller.slow_requested = _is_slow_held()
	equipment.reset_state()
	weapons.reset_state()
	var three_tools: Array[int] = [1, 2, 3]
	weapons.set_loadout(three_tools, 1)
	player.reset_state()
	_set_zoom(float(Tuning.VIEW.camera_size))
	director.reset_state()
	time_feedback = ""
	if history != null:
		history.clear()
		history.seed_checkpoint(capture_state())
	_update_hud()


func _close_repair() -> void:
	if time_controller != null:
		time_controller.set_repair_gesture_active(false)
	if equipment.repairing != &"":
		equipment.end_repair()
	SceneManager.close_popup(&"Repair")


func _on_player_wounded(amount: float) -> void:
	if is_instance_valid(feedback) and is_instance_valid(player):
		feedback.cue(&"player_hurt", player.global_position, clampf(amount / 15.0, 0.5, 1.35))
	if not _player_can_act() and SceneManager.has_popup(&"Repair"):
		_close_repair()


func capture_state() -> Dictionary:
	scrub_view.finish()
	return {
		"player": player.capture_state(),
		"equipment": equipment.capture_state(),
		"weapons": weapons.capture_state(),
		"director": director.capture_state(),
	}


func _restore_world(data: Dictionary, preview: bool = false) -> void:
	scrub_view.finish()
	_close_repair()
	var live_slots: Array[int] = _owned_tool_slots()
	var live_training: Array = equipment.training_protection.duplicate()
	if data.has("equipment") and data["equipment"] is Dictionary:
		equipment.restore_state((data["equipment"] as Dictionary).duplicate(true))
	if not live_training.is_empty():
		equipment.set_training_protection(live_training)
	if data.has("player") and data["player"] is Dictionary:
		player.restore_state(data["player"])
	if data.has("director") and data["director"] is Dictionary:
		director.restore_state(data["director"])
	if data.has("weapons") and data["weapons"] is Dictionary:
		weapons.restore_state(data["weapons"])
	if not live_slots.is_empty():
		weapons.available_tools.assign(live_slots)
	var restored_slot := clampi(int(weapons.selected_tool), 1, TOOL_IDS.size())
	if not live_slots.is_empty() and restored_slot not in live_slots:
		restored_slot = live_slots[0]
	weapons.selected_tool = restored_slot
	if preview:
		var weapons_data: Dictionary = data.get("weapons", {}) if data.get("weapons") is Dictionary else {}
		weapons.preview_overlay = (weapons_data.get("overlay", {}) as Dictionary).duplicate()
		if weapons.presentation != null:
			weapons.presentation.phase = float(weapons.preview_overlay.get("phase", weapons.presentation.phase))
		var preview_tool := clampi(int(weapons.preview_overlay.get("tool", weapons.selected_tool)), 1, TOOL_IDS.size())
		player.set_visual_tool(preview_tool)
	else:
		weapons.preview_overlay.clear()
		player.set_visual_tool(clampi(int(weapons.selected_tool), 1, TOOL_IDS.size()))
	weapons.rebuild_visuals(player)


func _on_emergency_started(_choice_count: int) -> void:
	_close_repair()
	weapons.cancel_input()
	player.reset_input()
	feedback.clear_effects()
	feedback.step(0.0, 0.0, 0.0, true, 0.0, weapons, equipment)
	_scrub_speed = 0.0
	_last_emergency_age = 0.0
	time_feedback = ""
	_update_hud()


func _on_emergency_selection_changed(_index: int, age_seconds: float, state: Dictionary) -> void:
	if not emergency_rewind.active:
		return
	var from_pose: Dictionary = scrub_view.capture_pose(player, director, weapons)
	scrub_view.finish()
	var effective_age := maxf(0.0, age_seconds)
	_scrub_speed = (effective_age - _last_emergency_age) / ScrubView.DURATION
	_last_emergency_age = effective_age
	if not state.is_empty():
		_restore_world(state, true)
		scrub_view.begin(from_pose, player, director, weapons)
	_update_hud()


func _on_emergency_confirmed(age_seconds: float, state: Dictionary) -> void:
	scrub_view.finish()
	feedback.clear_effects()
	if not state.is_empty():
		_restore_world(state, false)
	feedback.step(0.0, 0.0, 1.0, false, 0.0, weapons, equipment)
	feedback.cue(&"recovery_confirm", player.global_position)
	_last_emergency_age = 0.0
	if age_seconds == EmergencyRewind.CHECKPOINT_AGE:
		time_feedback = "Rewound to checkpoint"
	elif age_seconds > 0.0:
		time_feedback = "Rewound %.2fs" % age_seconds
	else:
		time_feedback = "Recovered"
	if time_controller != null:
		time_controller.slow_requested = _is_slow_held()
	_update_hud()


func _on_emergency_ended() -> void:
	scrub_view.finish()
	weapons.preview_overlay.clear()
	_last_emergency_age = 0.0
	_update_hud()


func _on_attempt_exhausted() -> void:
	if SceneManager.has_popup(&"Repair"):
		_close_repair()
	weapons.cancel_input()
	player.reset_input()
	_update_hud()


func _on_ui_clicked() -> void:
	feedback.cue(&"ui_click", player.global_position)


func _on_popup_opened(_key: StringName, _popup: Node) -> void:
	for button: BaseButton in _popup.find_children("*", "BaseButton", true, false):
		if not button.pressed.is_connected(_on_ui_clicked):
			button.pressed.connect(_on_ui_clicked)
	weapons.cancel_input()
	if _key == &"RunResult":
		_close_repair()
	if _key != &"Repair":
		player.reset_input()
	if time_controller != null:
		time_controller.slow_requested = _is_slow_held()


func _on_popup_closed(_key: StringName) -> void:
	if not is_inside_tree() or not player.is_inside_tree():
		return
	weapons.cancel_input()
	if _key != &"Repair":
		player.reset_input()
	if time_controller != null:
		time_controller.slow_requested = _is_slow_held()
	_update_hud()


func _on_state_changed(_old: int, _new: int) -> void:
	if is_instance_valid(feedback):
		feedback.reset_state()
	weapons.cancel_input()
	player.reset_input()
	_space_action_held = Input.is_action_pressed(SLOW_ACTION)
	if time_controller != null:
		time_controller.slow_requested = _is_slow_held() and GameState.is_playing()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(weapons):
		_close_repair()
		weapons.cancel_input()
		player.reset_input()
		_space_action_held = false
		Input.action_release(SLOW_ACTION)
		if time_controller != null:
			time_controller.slow_requested = false
			time_controller.set_repair_gesture_active(false)
		_repair_held = false
		GameState.pause()


func _on_weapon_resolved_hit(tool: StringName, result: Dictionary, context: Dictionary, enemy_id: int) -> void:
	if tool != &"beam" or not bool(context.get("piercing", false)):
		return
	if not bool(result.get("connected", false)) and float(result.get("dealt", 0.0)) <= 0:
		return
	for enemy in director.enemies:
		if is_instance_valid(enemy) and enemy.combat_id() == enemy_id:
			feedback.cue(&"pierce_hit", enemy.global_position, .8)
			return


func _on_repaired(tool: StringName, restored: float) -> void:
	var cue: StringName = &"repair_full" if equipment.is_full(tool) else &"repair_step"
	feedback.cue(cue, player.global_position, clampf(restored / 6.0, 0.3, 1.0))


func _update_hud() -> void:
	if not is_inside_tree() or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var in_emergency := emergency_rewind != null and emergency_rewind.active
	var world_scale := time_controller.world_scale if time_controller != null else 1.0
	time_cue.visible = not in_emergency
	time_cue.update_state(world_scale, in_emergency)
	var display_tool := clampi(int(weapons.preview_overlay.get("tool", weapons.selected_tool)), 1, TOOL_IDS.size())
	if player.visual_tool != display_tool:
		player.set_visual_tool(display_tool)
	status_hud.update_status(player, weapons, equipment)
	if is_instance_valid(player.visual):
		player.visual.held_tool.visible = not _owned_tool_slots().is_empty()
	status_hud.set_combat_hint(feedback.muted)
	var repair_open: bool = equipment.repairing != &"" or SceneManager.has_popup(&"Repair")
	var alpha: float = TimeStatusHUD.READOUT_ALPHA[status_hud.readout_mode] if not repair_open else 0.0
	hud.modulate.a = alpha
	hud.visible = alpha > 0.0
	slow_bar.modulate.a = alpha
	slow_bar.visible = alpha > 0.0
	if not hud.visible:
		return
	var next_text: String = "WASD move | 1/2/3 or Tab equip | +/- zoom | LMB draw / charge / hold | Space slow | Esc pause\n"
	next_text += "E toggle repair | Wheel/LMB/Enter emergency rewind | M sound | "
	if has_method("retry_room"):
		next_text += "R retry room | F10 encounters\n"
	else:
		next_text += "R reset | F1 target / F2 blue / F3 yellow / F4 orange | F5 pack | F6 encounter | F8 side / F9 front guard | Backspace clear\n"
	next_text += "Time %.0f / %.0f | Charges %d/%d | Enemies %d | World %.2fx\n" % [
		time_controller.meter, time_controller.capacity, time_controller.charges_remaining, time_controller.charges_per_attempt, director.enemies.size(), world_scale
	]
	next_text += weapons.status_text()
	next_text += "\n" + equipment.status_text() + " | " + director.status_text()
	if hud.text != next_text:
		hud.text = next_text
		slow_bar.position.y = hud.position.y + hud.get_minimum_size().y + 8
	slow_bar.max_value = time_controller.capacity
	slow_bar.value = time_controller.meter
