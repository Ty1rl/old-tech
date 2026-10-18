extends Node3D
# A small combat harness using the existing player and weapons, no campaign edits.
const PatternEnemy = preload("res://scenes/prototype/pattern_enemy.gd")
const Visual = preload("res://scenes/prototype/pattern_visual.gd")
const Weapons = preload("res://scenes/prototype/weapons.gd")
const Equipment = preload("res://scenes/prototype/equipment.gd")
const PlayerController = preload("res://scenes/prototype/player.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
const MODES := [&"loop", &"zigzag", &"pair", &"final_boss"]
var player: CharacterBody3D
var weapons: Node3D
var enemy: Node3D
var camera: Camera3D
var hud: Label
var chosen := 0
var saved: Dictionary = {}
var paused := false
var equipment := Equipment.new()

func _ready() -> void:
	var helper := Visual.new()
	helper.box(self, Vector3(0, -0.06, 0), Vector3(40, 0.1, 40), Color("494944"))
	for rectangle: Rect2 in Cover.RECTANGLES:
		helper.box(self, Vector3(rectangle.get_center().x, 0.7, rectangle.get_center().y), Vector3(rectangle.size.x, 1.4, rectangle.size.y), Color("686962"))
	helper.free()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("252a2b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c8c9c4")
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	player = preload("res://scenes/player.tscn").instantiate()
	player.set_script(PlayerController)
	player.equipment = equipment
	player.model = player.get_node("MeshInstance3D")
	player.camera = player.get_node("Camera3D")
	add_child(player)
	camera = player.camera
	# Fixed world camera, same 22-unit size and -55° pitch as the playable baseline.
	camera.reparent(self)
	camera.position = Vector3(0, 20, 14)
	camera.rotation_degrees = Vector3(-55, 0, 0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	camera.current = true
	weapons = Weapons.new()
	weapons.equipment = equipment
	add_child(weapons)
	enemy = PatternEnemy.new()
	add_child(enemy)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(20, 14)
	hud.add_theme_font_size_override("font_size", 20)
	layer.add_child(hud)
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

func aim() -> Vector3:
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
	var point := aim()
	var frozen := paused or Input.is_physical_key_pressed(KEY_F)
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
	if not paused and not Input.is_physical_key_pressed(KEY_F): weapons.handle_event(event, player, aim())
