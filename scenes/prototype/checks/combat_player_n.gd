extends SceneTree
# Round N Wave2: CombatPlayer scene + hit/time bridge, isolated from the arena.

const PLAYER_SCENE := preload("res://scenes/prototype/combat_player.tscn")
const CORE_SCENE := preload("res://scenes/time/time_core.tscn")
const MOVES: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
const EPS := 0.0001

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func near(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps


func tick() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


func steps(player: CombatPlayer, count: int, aim: Vector3, controller: TimeController = null) -> void:
	for i in range(count):
		await physics_frame
		if controller != null:
			controller.advance(tick())
		player.step(tick(), aim)


func release_moves() -> void:
	for action in MOVES:
		Input.action_release(action)


func run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)

	var player := PLAYER_SCENE.instantiate() as CombatPlayer
	root.add_child(player)
	expect(player != null, "combat_player.tscn root is a typed CombatPlayer (no runtime set_script)")
	expect(player.camera is Camera3D and player.model is Node3D and player.visual != null, "Camera/model/visual are authored scene references")
	expect(player.visual.get("character") != null, "Rig visual builds from its own scene node")
	for removed in ["health", "slow_charge", "equipment", "_slow_held", "_slow_release_required"]:
		expect(not removed in player, "Legacy player field '%s' is gone" % removed)
	expect(not player.has_method("status_text") and not player.has_method("_step_slow"), "No legacy slow/status helpers")
	expect(near(player.world_scale, 1.0) and player.can_act, "Unwired preview runs at normal time and can act")
	expect(near(player.take_damage(10.0), 0.0), "Unwired preview ignores damage instead of inventing health")

	var core: Node = CORE_SCENE.instantiate()
	root.add_child(core)
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	t.set_physics_process(false)
	player.time_controller = t
	player.reset_state()
	await physics_frame

	# Hit bridge
	var wounds: Array[float] = []
	player.wounded.connect(func(amount: float) -> void: wounds.append(amount))
	expect(near(player.take_damage(12.0), 12.0) and near(t.meter, 88.0), "take_damage spends time through TimeController.apply_hit")
	expect(wounds == [12.0], "wounded reports the time actually spent")

	# Movement at normal and slowed world time
	Input.action_press(&"move_right")
	await steps(player, 30, player.global_position + Vector3(5, 0, 0), t)
	var start_x := player.global_position.x
	await steps(player, 15, player.global_position + Vector3(5, 0, 0), t)
	var normal_distance := player.global_position.x - start_x
	var normal_speed := player.velocity.length()
	expect(normal_distance > 2.5, "Held move_right moves the player (%.2f m in 0.5 s)" % normal_distance)
	expect(near(normal_speed, 6.0, 0.05), "Velocity reaches the tuned top speed in world units")
	expect((-player.model.global_basis.z).dot(Vector3.RIGHT) > 0.99, "Model faces the aim point")
	t.slow_requested = true
	start_x = player.global_position.x
	await steps(player, 15, player.global_position + Vector3(5, 0, 0), t)
	var slow_distance := player.global_position.x - start_x
	expect(near(player.world_scale, 0.18) and near(slow_distance / normal_distance, 0.18, 0.02), "Slow scales displacement to world time (ratio %.3f)" % (slow_distance / normal_distance))
	expect(near(player.velocity.length(), normal_speed, 0.05), "Velocity stays in world units while slowed")
	t.slow_requested = false

	# Emergency freeze: no movement, no division by zero, cannot act
	t.apply_hit(500.0)
	expect(t.emergency_active and near(player.world_scale, 0.0) and not player.can_act, "Emergency freezes the player and blocks actions")
	var frozen_at := player.global_position
	await steps(player, 10, frozen_at + Vector3(5, 0, 0), t)
	expect(player.global_position.is_equal_approx(frozen_at), "Player does not move while frozen")
	expect(player.global_position.is_finite() and player.velocity.is_finite(), "No NaN/inf from a zero world scale")
	var before_wounds := wounds.size()
	expect(near(player.take_damage(30.0), 0.0) and wounds.size() == before_wounds, "Hits during an emergency are ignored and do not emit wounded")
	e.confirm()
	expect(player.can_act and t.protected, "Recovery restores actions with grace")
	expect(near(player.take_damage(20.0), 0.0) and wounds.size() == before_wounds, "Grace-absorbed hit emits no wounded")
	release_moves()

	# Exhaustion
	t.begin_attempt()
	for i in range(3):
		t.force_depletion()
		e.confirm()
	t.advance(2.0)
	t.apply_hit(500.0)
	expect(t.exhausted and not player.can_act, "Exhausted attempt blocks actions")

	# reset_state never creates attempts or replenishes time
	t.begin_attempt()
	t.apply_hit(30.0)
	t.force_depletion()
	e.confirm()
	var meter := t.meter
	var charges := t.charges_remaining
	player.reset_state(Vector3(3, 0.55, -2))
	expect(player.global_position.is_equal_approx(Vector3(3, 0.55, -2)) and player.velocity == Vector3.ZERO, "reset_state places the player")
	expect(near(t.meter, meter) and t.charges_remaining == charges, "reset_state leaves meter and charges untouched")

	# Snapshot schema
	player.velocity = Vector3(1, 0, 2)
	var snapshot := player.capture_state()
	expect(snapshot.keys().size() == 3 and snapshot.has("position") and snapshot.has("velocity") and snapshot.has("facing"), "Snapshot holds position/velocity/facing only")
	for value: Variant in snapshot.values():
		expect(typeof(value) != TYPE_OBJECT, "Snapshot values are plain data")
	player.reset_state()
	player.restore_state(snapshot)
	expect(player.position.is_equal_approx(snapshot.position) and player.velocity.is_equal_approx(snapshot.velocity), "restore_state reapplies the snapshot")
	expect(near(t.meter, meter), "Restoring a snapshot never touches time")

	player.set_visual_tool(4)
	expect(player.visual_tool == 3, "Only three weapons: tool index clamps to 3")

	player.free()
	core.free()
	floor_body.free()
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
