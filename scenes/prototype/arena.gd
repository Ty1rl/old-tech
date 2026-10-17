extends Node3D

const Tuning = preload("res://scenes/prototype/tuning.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const PlayerController = preload("res://scenes/prototype/player.gd")
const Weapons = preload("res://scenes/prototype/weapons.gd")
const Enemies = preload("res://scenes/prototype/enemies.gd")

var player: CharacterBody3D
var weapons: Node3D
var director: Node3D
var hud: Label
var slow_bar: ProgressBar
var aim: Vector3 = Vector3.ZERO
var aim_valid: bool = false


func _ready() -> void:
	_build_floor()
	player = PlayerScene.instantiate()
	player.set_script(PlayerController)
	player.camera = player.get_node("Camera3D")
	player.model = player.get_node("MeshInstance3D")
	add_child(player)
	player.camera.position = Vector3(0, 20, 14)
	player.camera.rotation_degrees = Vector3(-55, 0, 0)
	player.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	player.camera.size = 30
	player.camera.current = true
	weapons = Weapons.new()
	add_child(weapons)
	director = Enemies.new()
	add_child(director)
	_build_hud()
	GameState.state_changed.connect(_on_state_changed)
	GameState.start_game()
	reset_arena()


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
	slow_bar.max_value = Tuning.SLOW.capacity
	slow_bar.show_percentage = false
	slow_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(slow_bar)


func floor_aim(screen_position: Vector2) -> Vector3:
	var camera: Camera3D = player.camera
	var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(
		camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	aim_valid = hit != null
	return hit if aim_valid else aim


func _physics_process(delta: float) -> void:
	aim = floor_aim(get_viewport().get_mouse_position())
	player.step(delta, aim)
	player.position.x = clampf(player.position.x, -19.0, 19.0)
	player.position.z = clampf(player.position.z, -19.0, 19.0)
	# Engine.time_scale stays 1. Player/tools use real delta; enemies use world delta.
	director.step(delta * player.world_scale, player)
	weapons.step(delta, player, aim, director.enemies)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				reset_arena()
				return
			KEY_BACKSPACE:
				director.clear()
				return
			KEY_F1, KEY_F2, KEY_F3, KEY_F4:
				var kinds := [&"target", &"swarmer", &"brute", &"skirmisher"]
				director.spawn(kinds[event.physical_keycode - KEY_F1], _spawn_position())
				return
			KEY_F5:
				director.spawn_group()
				return
	aim = floor_aim(get_viewport().get_mouse_position())
	if aim_valid and not SceneManager.has_popup():
		weapons.handle_event(event, player, aim)


func _spawn_position() -> Vector3:
	return Vector3(clampf(aim.x, -17, 17), 0, clampf(aim.z, -17, 17))


func reset_arena() -> void:
	weapons.reset_state()
	player.reset_state()
	director.reset_state()
	_update_hud()


func _on_state_changed(_old: int, _new: int) -> void:
	weapons.cancel_input()
	player.reset_input()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(weapons):
		weapons.cancel_input()
		player.reset_input()
		if GameState.is_playing():
			GameState.pause()


func _update_hud() -> void:
	hud.text = "WASD move | 1/2/3 tools | LMB draw / click / hold | Space slow | Esc pause\n"
	hud.text += "R reset | F1 target | F2 swarm | F3 brute | F4 skirmisher | F5 mixed | Backspace clear\n"
	hud.text += "HP %.0f | Enemies %d | World %.2fx\n" % [player.health, director.enemies.size(), player.world_scale]
	hud.text += player.status_text() + "\n" + weapons.status_text()
	slow_bar.position.y = hud.position.y + hud.get_minimum_size().y + 8
	slow_bar.value = player.slow_charge
