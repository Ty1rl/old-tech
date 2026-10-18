extends SceneTree
var checks := 0
var failures: Array[String] = []
var scene: Node3D
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func mouse(down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	return e
func reset(index: int) -> void:
	scene.chosen = index
	scene.reset_enemy()
	scene.weapons.ring.flight_phase = "idle"
	scene.weapons.flash.pulses.clear()
	scene.weapons.flash.cooldown = 0
func real_shot(charge: bool, dt: float) -> void:
	var aim: Vector3 = scene.enemy.core_world_position()
	var w: Node3D = scene.weapons
	w.select_tool(2)
	w.handle_event(mouse(true), scene.player, aim)
	w.step(0.95 if charge else 0.01, scene.player, aim, [scene.enemy], 0)
	w.handle_event(mouse(false), scene.player, aim)
	for i in range(120): w.step(dt, scene.player, aim, [scene.enemy], dt)
func launch(path: Array[Vector3]) -> void:
	var w: Node3D = scene.weapons
	w.select_tool(1)
	w.handle_event(mouse(true), scene.player, path[0])
	for p in path:
		var move := InputEventMouseMotion.new()
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		w.handle_event(move, scene.player, p)
	w.handle_event(mouse(false), scene.player, path[-1])
	for i in range(180):
		w.step(1.0 / 60, scene.player, path[-1], [scene.enemy], 1.0 / 60)
		scene.enemy.step_enemy(1.0 / 60, null)
func run() -> void:
	scene = load("res://scenes/pattern_preview/main.gd").new()
	root.add_child(scene)
	scene.set_physics_process(false)
	await physics_frame
	for index in range(2):
		reset(index)
		var path: Array[Vector3] = []
		if index == 0:
			path = [Vector3(-1.3, 0, -1.3), Vector3(1.3, 0, -1.3), Vector3(1.3, 0, 1.3), Vector3(-1.3, 0, 1.3), Vector3(-1.3, 0, -1.3)]
		else:
			var points: Array = scene.enemy.cable_world_points()
			for i in range(points.size() / 2): path.append((points[i * 2] + points[i * 2 + 1]) * 0.5)
		launch(path)
		expect(scene.enemy.pattern_open, "Real raw cutter launch completes " + str(index))
		expect(scene.equipment.remaining(&"ring") == scene.equipment.capacity(&"ring") - 1, "Whole pattern costs one cutter launch " + str(index))
		real_shot(true, 1.0 / 60)
		expect(scene.enemy.health == 0, "Real charged traveling flash finishes open pattern " + str(index))
	for dt in [1.0 / 30, 1.0 / 60, 1.0 / 240]:
		reset(2)
		real_shot(false, dt)
		expect(scene.enemy.pair_progress == 1, "Actual quick shot finds raised A at dt " + str(dt))
		real_shot(false, dt)
		expect(scene.enemy.health == 0, "Actual quick B finishes at dt " + str(dt))
		reset(3)
		real_shot(false, dt)
		expect(scene.enemy.pair_progress == 1, "Boss actual A at dt " + str(dt))
		real_shot(false, dt)
		expect(scene.enemy.pattern_open, "Boss actual B opens finisher at dt " + str(dt))
		real_shot(true, dt)
		expect(scene.enemy.phase == 1, "Boss actual finisher advances at dt " + str(dt))
	# Warning → commitment → recovery; no contact damage during warning/freeze.
	reset(0)
	scene.player.position = Vector3(0, 0, 1.4)
	var hp: float = scene.time_controller.meter
	scene.enemy.step_enemy(0.01, scene.player)
	expect(scene.enemy.attack_phase == &"windup" and scene.time_controller.meter == hp, "Contact warns before damage")
	var winding: Dictionary = scene.enemy.capture_state()
	scene.enemy.step_enemy(0, scene.player)
	expect(scene.enemy.attack_timer == winding.attack_timer, "Frozen world stops attack timer")
	scene.enemy.step_enemy(0.81, scene.player)
	expect(scene.enemy.attack_phase == &"commit" and scene.time_controller.meter == hp, "Windup leads to visible commitment")
	scene.enemy.step_enemy(0.19, scene.player)
	expect(scene.enemy.attack_phase == &"recover" and scene.time_controller.meter < hp, "Committed attack hits once then recovers")
	hp = scene.time_controller.meter
	scene.enemy.step_enemy(1, scene.player)
	expect(scene.enemy.attack_phase == &"recover" and scene.time_controller.meter == hp, "Long recovery leaves an action window")
	scene.enemy.restore_state(winding)
	expect(scene.enemy.attack_phase == &"windup" and scene.enemy.attack_timer == winding.attack_timer, "Rewind restores attack warning")
	var position_before: Vector3 = scene.player.position
	var timer_before: float = scene.enemy.attack_timer
	scene.player.velocity = Vector3(3, 0, 0)
	scene.paused = true
	scene._physics_process(0.25)
	expect(scene.player.position == position_before and scene.enemy.attack_timer == timer_before, "Preview pause freezes movement and world attack timer")
	scene.free()
	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
