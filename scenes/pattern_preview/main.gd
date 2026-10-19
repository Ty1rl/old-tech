extends CombatArena
# A small combat harness using the existing player and weapons, no campaign edits.
const PatternEnemy = preload("res://scenes/prototype/pattern_enemy.gd")
const Visual = preload("res://scenes/prototype/pattern_visual.gd")
const MODES := [&"loop", &"zigzag", &"pair", &"final_boss"]
var enemy: Node3D
var camera: Camera3D
var chosen := 0
var saved: Dictionary = {}
var paused := false

func _ready() -> void:
	super._ready()
	director.clear()
	camera = player.camera
	enemy = PatternEnemy.new()
	add_child(enemy)
	reset_enemy()

func reset_enemy() -> void:
	weapons.cancel_input()
	equipment.reset_state()
	player.reset_state()
	player.position = Vector3(0, 0, 6)
	enemy.configure(MODES[chosen], Vector3.ZERO, 55)
	enemy.position = Vector3.ZERO
	enemy.facing = Vector3.BACK
	saved = enemy.capture_state()

func _pattern_aim() -> Vector3:
	var screen := get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, 0)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	var result: Vector3 = hit if hit != null else Vector3.ZERO
	var nearest := 22.0
	if weapons.selected_tool == 1 and enemy.has_cuttable_part():
		var points: Array = enemy.cable_world_points()
		for i in range(points.size() / 2):
			var a := camera.unproject_position(points[i * 2])
			var b := camera.unproject_position(points[i * 2 + 1])
			var t := clampf((screen - a).dot(b - a) / maxf(0.001, a.distance_squared_to(b)), 0, 1)
			var d := screen.distance_to(a.lerp(b, t))
			if d < nearest:
				nearest = d
				result = (points[i * 2] as Vector3).lerp(points[i * 2 + 1], t)
	elif weapons.selected_tool == 2 and enemy.is_core_exposed():
		var core: Vector3 = enemy.core_world_position()
		if screen.distance_to(camera.unproject_position(core)) < 22: result = core
	result.y = 0
	return result

func _physics_process(delta: float) -> void:
	var point := _pattern_aim()
	var frozen := paused or Input.is_physical_key_pressed(KEY_F)
	time_controller.slow_requested = Input.is_action_pressed(SLOW_ACTION) and not frozen
	time_controller.advance(0.0 if frozen else delta)
	if not frozen: player.step(delta, point)
	var world_delta: float = 0.0 if frozen else delta * player.world_scale
	weapons.step(0 if frozen else delta, player, point, [enemy], world_delta)
	enemy.step_enemy(world_delta, player, [enemy])
	player.set_visual_tool(weapons.selected_tool)
	hud.text = "PATTERN TRIAL · %s · HP %.0f · phase %d\n1 cutter / 2 yellow / 3 heat · WASD move · Space slows · F freezes\nF1–F4 enemy · R restart · P pause · V save / B rewind enemy\n%s · %s" % [MODES[chosen], enemy.health, enemy.phase + 1, str(enemy.lesson_state()), weapons.last_feedback]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_F1, KEY_F2, KEY_F3, KEY_F4]:
			chosen = event.physical_keycode - KEY_F1
			reset_enemy()
		elif event.physical_keycode == KEY_R: reset_enemy()
		elif event.physical_keycode == KEY_P: paused = not paused
		elif event.physical_keycode == KEY_V: saved = enemy.capture_state()
		elif event.physical_keycode == KEY_B: enemy.restore_state(saved)
	if not paused and not Input.is_physical_key_pressed(KEY_F): weapons.handle_event(event, player, _pattern_aim())
