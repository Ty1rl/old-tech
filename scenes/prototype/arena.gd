extends Node3D

const CreatureVisual = preload("res://scenes/prototype/creature_visual.gd")
const MuseumEnvironment = preload("res://scenes/prototype/museum_environment.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const PlayerController = preload("res://scenes/prototype/player.gd")
const Weapons = preload("res://scenes/prototype/weapons.gd")
const Enemies = preload("res://scenes/prototype/enemies.gd")
const Equipment = preload("res://scenes/prototype/equipment.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
const CombatFeedback = preload("res://scenes/prototype/combat_feedback.gd")
const TimeCue = preload("res://scenes/prototype/time_cue.gd")
const AimAssist = preload("res://scenes/prototype/aim_assist.gd")
const ScrubView = preload("res://scenes/prototype/scrub_view.gd")
const History = preload("res://scenes/prototype/history.gd")
const StatusHud = preload("res://scenes/prototype/status_hud.gd")

var museum: Node3D
var equipment: RefCounted = Equipment.new()
var cover: RefCounted = Cover.new()

var player: CharacterBody3D
var weapons: Node3D
var director: Node3D
var hud: Label
var slow_bar: ProgressBar
var status_hud: Control
var aim: Vector3 = Vector3.ZERO
var aim_valid: bool = false
var history: RefCounted = History.new()
var _space_held := false
var _space_release_required := false
var _repair_held := false
var _inspection_clock := 0.0
var _preview: Dictionary = {}
var time_feedback := ""
var time_cue: CanvasLayer
var feedback: Node3D
var scrub_view: RefCounted = ScrubView.new()
var _scrub_speed := 0.0


func _ready() -> void:
	_build_floor()
	_build_cover()
	museum = create_museum()
	museum.name = "MuseumEnvironment"
	museum.build()
	museum.apply_to_arena(self)
	player = PlayerScene.instantiate()
	player.set_script(PlayerController)
	player.equipment = equipment
	player.camera = player.get_node("Camera3D")
	player.model = player.get_node("MeshInstance3D")
	add_child(player)
	player.camera.position = Vector3(0, 20, 14)
	player.camera.rotation_degrees = Vector3(-55, 0, 0)
	player.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	player.camera.fov = float(Tuning.VIEW.fov)
	player.camera.size = float(Tuning.VIEW.camera_size)
	player.camera.current = true
	weapons = Weapons.new()
	weapons.equipment = equipment
	weapons.cover = cover
	add_child(weapons)
	director = Enemies.new()
	director.cover = cover
	add_child(director)
	feedback = CombatFeedback.new()
	add_child(feedback)
	weapons.combat_event.connect(feedback.cue)
	equipment.repaired.connect(_on_repaired)
	_build_hud()
	time_cue = TimeCue.new()
	add_child(time_cue)
	GameState.state_changed.connect(_on_state_changed)
	SceneManager.popup_opened.connect(_on_popup_opened)
	SceneManager.popup_closed.connect(_on_popup_closed)
	GameState.start_game()
	reset_arena()
	CreatureVisual.warmup(self)


func create_museum() -> Node3D:
	return MuseumEnvironment.new()


func _set_zoom(value: float) -> void:
	player.camera.size = clampf(value, 10.0, 32.0)
	player.camera.fov = float(Tuning.VIEW.fov)
	player.camera.position = Vector3(0, 20, 14) * (player.camera.size / float(Tuning.VIEW.camera_size))


func _switch_tool(index: int) -> void:
	if index not in weapons.available_tools or index == weapons.selected_tool: return
	var continue_space := _space_held and not _space_release_required
	if history.inspecting:
		_finish_inspection(false) # Switching never commits an accidental rewind.
	weapons.select_tool(index)
	if continue_space:
		_space_release_required = false
		player._slow_release_required = false
		if index == 4: _begin_inspection()
		else: player._step_slow(0.0, 4 in weapons.available_tools)
	_update_hud()


func _cycle_tool(backward: bool = false) -> void:
	var tools: Array[int] = weapons.available_tools
	if tools.is_empty(): return
	var current := tools.find(weapons.selected_tool)
	_switch_tool(tools[posmod(current + (-1 if backward else 1), tools.size())])


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
	slow_bar.max_value = equipment.capacity(&"clock")
	slow_bar.show_percentage = false
	slow_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(slow_bar)
	status_hud = StatusHud.new()
	layer.add_child(status_hud)


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
	if history.inspecting:
		scrub_view.step(delta)
	_scrub_speed *= exp(-maxf(delta, 0.0) * 8.0)


func _physics_process(delta: float) -> void:
	if SceneManager.has_popup(&"Developer") or SceneManager.has_popup(&"Settings"): return
	if history.inspecting:
		feedback.step(delta, 0.0, 0.0, true, _scrub_speed, weapons, equipment)
		_step_inspection(delta)
		_update_hud()
		return
	if player.health <= 0.0:
		player.world_scale = 1.0
		feedback.step(delta, 0.0, 1.0, false, 0.0, weapons, equipment)
		_update_hud()
		return # Keep the final live history available for a do-over.
	aim = floor_aim(get_viewport().get_mouse_position())
	var repair_slow: bool = 4 in weapons.available_tools and equipment.repairing != &"" and equipment.repairing != &"clock"
	player.step(delta, aim, _space_held and not _space_release_required and weapons.selected_tool != 4 and 4 in weapons.available_tools, repair_slow)
	player.position.x = clampf(player.position.x, -19.0, 19.0)
	player.position.z = clampf(player.position.z, -19.0, 19.0)
	var world_delta: float = delta * player.world_scale
	var health_before: float = player.health
	director.step(world_delta, player)
	if player.health < health_before and SceneManager.has_popup(&"Repair"):
		_close_repair()
	weapons.step(delta, player, aim, director.enemies, world_delta)
	feedback.step(delta, world_delta, player.world_scale, false, 0.0, weapons, equipment)
	history.record(delta, capture_state)
	_update_hud()


# Handle mode exits before popup controls or weapon input can consume them.
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if code == KEY_E and not event.pressed:
			_repair_held = false
			_close_repair()
		if code == KEY_SPACE and not event.echo:
			_space_held = event.pressed
			if not event.pressed:
				if history.inspecting:
					_finish_inspection(true)
				_space_release_required = false
				player._step_slow(0.0, false)
			elif not _space_release_required and weapons.selected_tool == 4 and not SceneManager.has_popup():
				_begin_inspection()
			get_viewport().set_input_as_handled()
			return
		if code == KEY_F10 and event.pressed and not event.echo and SceneManager.developer_tools:
			if SceneManager.has_popup(&"Developer"): SceneManager.close_popup(&"Developer")
			else: SceneManager.push_popup(&"Developer")
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
	if event is InputEventKey and event.pressed and not event.echo and not SceneManager.has_popup():
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if code == KEY_TAB or (code >= KEY_1 and code <= KEY_4):
			if code == KEY_TAB: _cycle_tool(event.shift_pressed)
			else: _switch_tool(code - KEY_1 + 1)
			get_viewport().set_input_as_handled()
			return
	if history.inspecting:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_seek_inspection(history.selected_seconds_ago + Tuning.REWIND.scroll_step)
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_seek_inspection(history.selected_seconds_ago - Tuning.REWIND.scroll_step)
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			_finish_inspection(false)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if history.inspecting:
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
		if code >= KEY_1 and code <= KEY_4:
			_switch_tool(code - KEY_1 + 1)
			return
		match code:
			KEY_EQUAL, KEY_PLUS:
				_set_zoom(player.camera.size - 2)
				return
			KEY_MINUS:
				_set_zoom(player.camera.size + 2)
				return
			KEY_F7:
				status_hud.cycle_readout()
				_update_hud()
				return
			KEY_E:
				if not _repair_held and player.health > 0.0:
					_repair_held = true
					var tool: StringName = Weapons.TOOL_IDS[weapons.selected_tool - 1]
					if not equipment.is_full(tool):
						SceneManager.push_popup(&"Repair", {"equipment": equipment, "tool": tool})
				return
			KEY_R:
				reset_arena()
				return
			KEY_BACKSPACE:
				director.clear()
				history.clear()
				return
			KEY_F1, KEY_F2, KEY_F3, KEY_F4:
				var kinds := [&"target", &"blue", &"yellow", &"orange"]
				director.spawn(kinds[code - KEY_F1], _spawn_position())
				history.clear()
				return
			KEY_F5:
				director.spawn_group()
				history.clear()
				return
			KEY_F8:
				director.spawn(&"side_guard", _spawn_position())
				history.clear()
				return
			KEY_F9:
				reset_arena()
				director.clear()
				_set_zoom(float(Tuning.VIEW.showcase_size))
				director.spawn(&"front_guard", Vector3(0, 0, -7))
				_update_hud()
				return
			KEY_F6:
				reset_arena()
				director.start_encounter()
				return
	aim = floor_aim(get_viewport().get_mouse_position())
	if aim_valid and player.health > 0.0:
		weapons.handle_event(event, player, aim)


func _spawn_position() -> Vector3:
	return Vector3(clampf(aim.x, -17, 17), 0, clampf(aim.z, -17, 17))


func reset_arena() -> void:
	if history.inspecting:
		_finish_inspection(false)
	_close_repair()
	scrub_view.finish()
	feedback.reset_state()
	history.clear()
	_space_release_required = _space_held
	_repair_held = false
	equipment.reset_state()
	weapons.reset_state()
	player.reset_state()
	_set_zoom(float(Tuning.VIEW.camera_size))
	director.reset_state()
	time_feedback = ""
	_update_hud()


func _close_repair() -> void:
	if equipment.repairing != &"":
		equipment.end_repair()
	SceneManager.close_popup(&"Repair")


func capture_state() -> Dictionary:
	return {"player": player.capture_state(), "equipment": equipment.capture_state(),
		"weapons": weapons.capture_state(), "director": director.capture_state()}


func _restore_world(data: Dictionary, live_clock: float) -> void:
	scrub_view.finish()
	_close_repair()
	var gear: Dictionary = data.equipment.duplicate(true)
	gear.remaining["clock"] = live_clock
	equipment.restore_state(gear)
	player.restore_state(data.player)
	director.restore_state(data.director)
	weapons.restore_state(data.weapons)
	weapons.select_tool(4) # Equipping the clock remains the player's current intent.
	if history.inspecting:
		weapons.preview_overlay = data.weapons.get("overlay", {}).duplicate()
		weapons.presentation.phase = float(weapons.preview_overlay.get("phase",weapons.presentation.phase))
		player.set_visual_tool(int(weapons.preview_overlay.get("tool",4)))
	weapons._rebuild_visuals(player, aim)


func _begin_inspection() -> void:
	if history.inspecting or 4 not in weapons.available_tools or weapons.selected_tool != 4 or SceneManager.has_popup() or not equipment.can_use(&"clock"):
		return
	weapons.cancel_input()
	player.reset_input()
	_preview = capture_state()
	history.begin_inspection(_preview)
	if not history.inspecting:
		return
	_inspection_clock = equipment.remaining(&"clock")
	feedback.clear_effects()
	feedback.step(0, 0, 0, true, 0, weapons, equipment)
	_scrub_speed = 0.0
	time_feedback = ""
	_update_hud()


func inspection_cost() -> float:
	return history.selected_seconds_ago * Tuning.REWIND.jump_cost


func _available_clock(data: Dictionary) -> float:
	return minf(_inspection_clock, float(data.equipment.remaining.clock))


func _seek_inspection(seconds_ago: float) -> void:
	if not history.inspecting:
		return
	var previous: float = history.selected_seconds_ago
	var candidate: Dictionary = history.seek(seconds_ago)
	if inspection_cost() > _available_clock(candidate) + 0.000001:
		history.seek(previous)
		time_feedback = "Not enough clock condition for that jump"
		return
	var from_pose: Dictionary = scrub_view.capture_pose(player, director, weapons)
	scrub_view.finish()
	_preview = candidate
	time_feedback = ""
	_scrub_speed = (history.selected_seconds_ago - previous) / ScrubView.DURATION
	_restore_world(_preview, _inspection_clock)
	scrub_view.begin(from_pose, player, director, weapons)
	_update_hud()


func _step_inspection(delta: float) -> void:
	_inspection_clock = maxf(0.0, _inspection_clock - maxf(delta, 0.0) * Tuning.REWIND.browse_drain)
	equipment.spend(&"clock", maxf(0.0, equipment.remaining(&"clock") - _inspection_clock))
	if _inspection_clock <= 0.000001 or inspection_cost() > _available_clock(_preview) + 0.000001:
		_finish_inspection(false)
		time_feedback = "Clock spent · returned to present"


func _finish_inspection(commit: bool) -> void:
	if not history.inspecting:
		return
	scrub_view.finish()
	feedback.clear_effects()
	var age: float = history.selected_seconds_ago
	var cost := inspection_cost()
	var can_commit: bool = commit and cost <= _available_clock(_preview) + 0.000001
	var data: Dictionary = history.commit_inspection() if can_commit else history.cancel_inspection()
	var clock: float = _inspection_clock
	if can_commit and age > 0.0:
		clock = maxf(0.0, minf(clock, float(data.equipment.remaining.clock)) - cost)
	_restore_world(data, clock)
	feedback.step(0, 0, 1, false, 0, weapons, equipment)
	_space_release_required = _space_held
	_preview = {}
	time_feedback = "Rewound %.2fs" % age if can_commit and age > 0.0 else "Present"
	_update_hud()


func _on_popup_opened(_key: StringName, _popup: Node) -> void:
	if history.inspecting:
		_finish_inspection(false)
	weapons.cancel_input()
	player.reset_input()
	_space_release_required = _space_held


func _on_popup_closed(_key: StringName) -> void:
	weapons.cancel_input()
	player.reset_input()
	_space_release_required = _space_held


func _on_state_changed(_old: int, _new: int) -> void:
	if is_instance_valid(feedback):
		feedback.reset_state()
	if history.inspecting:
		_finish_inspection(false)
	weapons.cancel_input()
	player.reset_input()
	_space_release_required = Input.is_physical_key_pressed(KEY_SPACE)
	_space_held = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(weapons):
		if history.inspecting:
			_finish_inspection(false)
		_close_repair()
		weapons.cancel_input()
		player.reset_input()
		_space_held = false
		_space_release_required = true
		_repair_held = false
		if GameState.is_playing():
			GameState.pause()


func _on_repaired(_tool: StringName, restored: float) -> void:
	feedback.cue(&"repair_step", player.global_position, clampf(restored / 6.0, 0.3, 1.0))


func _update_hud() -> void:
	time_cue.update_state(player.world_scale,history.inspecting)
	var display_tool := int(weapons.preview_overlay.get("tool",weapons.selected_tool))
	if player.visual_tool != display_tool:
		player.set_visual_tool(display_tool)
	status_hud.update_status(player, weapons, equipment)
	status_hud.visible = equipment.repairing == &""
	if is_instance_valid(player.visual): player.visual.held_tool.visible = not weapons.available_tools.is_empty()
	if history.inspecting:
		status_hud.selected = display_tool - 1
		status_hud.caption = StatusHud.NAMES[display_tool-1] + " · recorded"
	status_hud.set_combat_hint(feedback.muted)
	var clock_after: float = _available_clock(_preview) - inspection_cost() if history.inspecting else equipment.remaining(&"clock")
	status_hud.update_timeline(history, inspection_cost(), time_feedback, clock_after)
	var alpha: float = StatusHud.READOUT_ALPHA[status_hud.readout_mode] if equipment.repairing == &"" else 0.0
	hud.modulate.a = alpha
	hud.visible = alpha > 0.0
	slow_bar.modulate.a = alpha
	slow_bar.visible = alpha > 0.0
	hud.text = "WASD move | 1/2/3/4 or Tab equip | +/- zoom | LMB draw / charge / hold | Space slow / clock inspect | Esc pause\n"
	hud.text += "Hold E repair selected | Wheel scrub clock | R reset | F1 target / F2 blue / F3 yellow / F4 orange | F5 pack | F6 encounter | F8 side / F9 front guard | M sound | Backspace clear\n"
	hud.text += "HP %.0f | Enemies %d | World %.2fx\n" % [player.health, director.enemies.size(), player.world_scale]
	hud.text += player.status_text() + "\n" + weapons.status_text()
	hud.text += "\n" + equipment.status_text() + " | " + director.status_text()
	slow_bar.position.y = hud.position.y + hud.get_minimum_size().y + 8
	slow_bar.value = player.slow_charge
