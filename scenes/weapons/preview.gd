extends Node3D
## Manual component bench; isolated from consumers being migrated by other seats.
@onready var weapons: WeaponController = $Weapons
@onready var player: Node3D = $Player
@onready var targets: Node3D = $Targets
@onready var time: TimeController = $TimeCore/TimeController
@onready var readout: Label = $CanvasLayer/Readout
var saved: Dictionary = {}
func _ready() -> void:
	weapons.time_controller = time
	time.begin_attempt()
	reset_targets()
func reset_targets() -> void:
	weapons.reset_state()
	weapons.equipment.reset_state()
	var kinds: Array[StringName] = [&"blue", &"yellow", &"yellow", &"orange"]
	var positions: Array[Vector3] = [Vector3(-3, 0, -7), Vector3(0, 0, -8), Vector3(0, 0, -11), Vector3(3, 0, -7)]
	for i in range(targets.get_child_count()):
		var target: Node3D = targets.get_child(i)
		target.configure(kinds[i], positions[i], i + 1)
		target.facing = Vector3.BACK
		target.visible = true
	player.position = Vector3.ZERO
func aim() -> Vector3:
	var camera: Camera3D = player.camera
	var screen := get_viewport().get_mouse_position()
	var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	return hit if hit != null else Vector3(0, 0, -6)
func advance(real_delta: float, point: Vector3, world_delta: float) -> void:
	player.aim_at(point, weapons.selected_tool, world_delta)
	weapons.step(real_delta, player, point, targets.get_children(), world_delta)
	for target: Node3D in targets.get_children():
		target.step_enemy(world_delta, null)
		target.visible = target.health > 0
	readout.text = "WEAPON SCENE BENCH · 1 cutter / 2 flash / 3 bellows · Space manual slow\nMouse: draw / charge / hold · R reset · V save / B restore world\n%s\n%s · time %.0f / %.0f · charges %d" % [weapons.status_text(), weapons.equipment.status_text(), time.meter, time.capacity, time.charges_remaining]
func _physics_process(delta: float) -> void:
	time.slow_requested = Input.is_physical_key_pressed(KEY_SPACE)
	advance(delta, aim(), delta * time.world_scale)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R: reset_targets()
		elif event.physical_keycode == KEY_V: saved = {"weapons":weapons.capture_state(), "equipment":weapons.equipment.capture_state(), "targets":targets.get_children().map(func(t): return t.capture_state())}
		elif event.physical_keycode == KEY_B and not saved.is_empty():
			weapons.restore_state(saved.weapons)
			weapons.equipment.restore_state(saved.equipment)
			for i in range(targets.get_child_count()): targets.get_child(i).restore_state(saved.targets[i])
	weapons.handle_event(event, player, aim())
