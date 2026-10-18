extends SceneTree

const ScrubView = preload("res://scenes/prototype/scrub_view.gd")
var failures: Array[String] = []
var checks := 0
var arena: Node3D


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)


func pulse(pos: Vector3) -> Dictionary:
	return {"pos": pos, "dir": Vector2.RIGHT, "speed": 10.0,
		"remaining_range": 15.0, "radius": 0.2, "damage": 30.0, "charge": 0.5}


func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	arena.director.clear()
	arena.director.spawn(&"target", Vector3(0, 0, -5))
	var enemy: Node3D = arena.director.enemies[0]
	var enemy_id: int = enemy.combat_id()
	var view := ScrubView.new()
	arena.player.position = Vector3(0, 0.55, 0)
	arena.player.model.basis = Basis.IDENTITY
	enemy.position = Vector3(0, 0, -5)
	enemy.visual_root.basis = Basis.IDENTITY
	arena.weapons.ring.flight_phase = "stroke"
	arena.weapons.ring.flight_points.assign([Vector3(0, 0, -4), Vector3(5, 0, -4)])
	arena.weapons.ring.head = Vector3(0, 0, -4)
	arena.weapons.flash.pulses.assign([pulse(Vector3(0, 0, -2))])
	arena.player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	enemy.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	var old := view.capture_pose(arena.player, arena.director, arena.weapons)
	var old_bytes := var_to_bytes(old)
	arena.player.position.x = 8
	arena.player.model.basis = Basis(Vector3.UP, PI * 0.5)
	enemy.position.x = 8
	enemy.visual_root.basis = Basis(Vector3.UP, PI * 0.5)
	enemy.health = 23
	enemy.flash_timer = 0.12
	enemy.facing = Vector3.RIGHT
	# Visual facing is captured independently of the authoritative facing vector.
	enemy.visual_root.basis = Basis(Vector3.UP, PI * 0.5)
	arena.weapons.ring.head = Vector3(8, 0, -4)
	arena.weapons.flash.pulses[0].pos = Vector3(8, 0, -2)
	arena.weapons.flash.cooldown = 0.8
	var target: Dictionary = arena.capture_state()
	var target_bytes := var_to_bytes(target)
	var target_pose := view.capture_pose(arena.player, arena.director, arena.weapons)
	view.begin(old, arena.player, arena.director, arena.weapons)
	expect(view.active and arena.player.position == old.player.origin, "Begin displays old position immediately")
	expect(arena.player.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF
		and enemy.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "Preview disables physics interpolation on affected roots")
	view.step(-1.0)
	expect(arena.player.position.x == 0.0, "Negative render delta does not reverse time")
	view.step(ScrubView.DURATION * 0.25)
	expect(is_equal_approx(arena.player.position.x, 1.25), "Quarter transition uses smoothstep easing")
	view.step(ScrubView.DURATION * 0.25)
	expect(is_equal_approx(arena.player.position.x, 4.0) and is_equal_approx(enemy.position.x, 4.0), "Halfway player and enemy positions blend")
	expect(arena.player.model.basis.is_equal_approx(Basis(Vector3.UP, PI * 0.25))
		and enemy.visual_root.basis.is_equal_approx(Basis(Vector3.UP, PI * 0.25)), "Model and enemy visual orientation blend")
	expect(arena.weapons.ring.head.is_equal_approx(Vector3(4, 0, -4))
		and arena.weapons.flash.pulses[0].pos.is_equal_approx(Vector3(4, 0, -2)), "Ring and matching flash pulse positions blend")
	expect(enemy.health == 23 and enemy.flash_timer == 0.12 and enemy.facing == Vector3.RIGHT
		and arena.weapons.flash.cooldown == 0.8 and arena.weapons.flash.pulses[0].remaining_range == 15.0,
		"Preview preserves health, facing gameplay vector, feedback and flight timers")
	expect(var_to_bytes(old) == old_bytes and var_to_bytes(target) == target_bytes, "Pose and gameplay snapshots remain immutable")
	var intermediate := view.capture_pose(arena.player, arena.director, arena.weapons)
	view.finish()
	expect(view.capture_pose(arena.player, arena.director, arena.weapons) == target_pose and not view.active,
		"Finish returns exact target pose")
	expect(arena.player.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON
		and enemy.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_INHERIT, "Finish restores original interpolation modes")
	expect(arena.capture_state() == target, "Finish restores exact gameplay state with no events or timer changes")
	arena.player.position.x = -4
	arena.weapons.ring.head.x = -4
	arena.weapons.flash.pulses[0].pos.x = -4
	view.begin(intermediate, arena.player, arena.director, arena.weapons)
	expect(arena.player.position.x == 4.0 and arena.weapons.ring.head.x == 4.0, "Rapid reversal starts from current displayed intermediate pose")
	view.step(ScrubView.DURATION * 0.5)
	expect(is_equal_approx(arena.player.position.x, 0.0) and is_equal_approx(arena.weapons.ring.head.x, 0.0), "Rapid reversal blends without snapping to previous snapshot")
	view.step(1.0)
	expect(not view.active and arena.player.position.x == -4.0 and arena.weapons.ring.head.x == -4.0,
		"Oversized delta ends exactly at target")
	view.finish()
	expect(arena.player.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON, "Repeated finish is harmless")
	old = view.capture_pose(arena.player, arena.director, arena.weapons)
	arena.director.clear()
	arena.director.spawn(&"target", Vector3(12, 0, -5))
	enemy = arena.director.enemies[0]
	enemy.rewind_id = enemy_id
	arena.director.spawn(&"target", Vector3(-10, 0, -5))
	var added: Node3D = arena.director.enemies[1]
	var added_position := added.position
	view.begin(old, arena.player, arena.director, arena.weapons)
	expect(enemy.position.x == 8.0, "Recreated enemy matches old pose by stable combat ID")
	expect(added.position == added_position, "New enemy snaps to authoritative position")
	view.step(ScrubView.DURATION * 0.5)
	expect(is_equal_approx(enemy.position.x, 10.0) and added.position == added_position, "Recreated enemy blends while missing old entity is safe")
	view.finish()
	expect(enemy.position.x == 12.0, "Recreated enemy finish returns exact target")
	old = view.capture_pose(arena.player, arena.director, arena.weapons)
	enemy.visual_root.scale = Vector3(1.2, 1.0, 0.8)
	view.begin(old, arena.player, arena.director, arena.weapons)
	view.step(ScrubView.DURATION * 0.5)
	expect(enemy.visual_root.scale.is_equal_approx(Vector3(1.2, 1.0, 0.8)), "Entity size snaps to target while only positions and orientations blend")
	view.finish()
	old = view.capture_pose(arena.player, arena.director, arena.weapons)
	arena.director.clear()
	arena.weapons.flash.pulses.clear()
	arena.weapons.ring.flight_phase = "idle"
	view.begin(old, arena.player, arena.director, arena.weapons)
	view.step(ScrubView.DURATION * 0.5)
	expect(arena.director.enemies.is_empty() and arena.weapons.flash.pulses.is_empty()
		and arena.weapons.ring.flight_phase == "idle", "Deleted enemies and attacks stay deleted without ghosts")
	view.finish()
	old = view.capture_pose(arena.player, arena.director, arena.weapons)
	view.begin(old, arena.player, arena.director, arena.weapons)
	# Let the native mixer register playback before testing immediate node destruction.
	await create_timer(.1).timeout
	arena.feedback.reset_state()
	arena.free()
	view.step(ScrubView.DURATION * 0.5)
	view.finish()
	expect(not view.active, "Freed arena nodes can be stepped and finished safely")
	# Let native compressed playback leave the mixer before process teardown.
	await create_timer(.3).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
