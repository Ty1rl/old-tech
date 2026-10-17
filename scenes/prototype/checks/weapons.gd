extends SceneTree

const Tuning = preload("res://scenes/prototype/tuning.gd")

var failures: Array[String] = []
var checks: int = 0


class FakeEnemy extends Node3D:
	const TuningRef = preload("res://scenes/prototype/tuning.gd")
	var kind: StringName = &"target"
	var radius: float = 0.7
	var health: float = 100.0
	var facing: Vector3 = Vector3(0.0, 0.0, 1.0)
	var hit_count: int = 0
	var last_contact: Vector3 = Vector3.ZERO
	var last_armored: bool = false

	func _init(p_kind: StringName, pos: Vector3, p_facing: Vector3 = Vector3(0.0, 0.0, 1.0)) -> void:
		kind = p_kind
		var cfg: Dictionary = TuningRef.ENEMIES.get(String(p_kind), TuningRef.ENEMIES["target"])
		health = float(cfg["health"])
		radius = float(cfg["radius"])
		position = pos
		var f2 := Vector2(p_facing.x, p_facing.z)
		facing = Vector3(f2.x, 0.0, f2.y).normalized() if f2.length_squared() > 1e-6 else Vector3(0.0, 0.0, 1.0)

	func hit(amount: float, contact_world: Vector3) -> Dictionary:
		if health <= 0.0 or amount <= 0.0:
			return {"dealt": 0.0, "armored": false, "killed": false}
		var armored := false
		var actual := amount
		if kind == &"brute":
			var to_contact := Vector2(contact_world.x - global_position.x, contact_world.z - global_position.z)
			var f_xz := Vector2(facing.x, facing.z).normalized()
			if to_contact.length_squared() > 1e-6 and absf(f_xz.angle_to(to_contact)) <= float(TuningRef.ARMOR.front_half_angle):
				armored = true
				actual *= float(TuningRef.ARMOR.front_multiplier)
		var dealt := minf(health, actual)
		health = maxf(0.0, health - actual)
		hit_count += 1
		last_contact = contact_world
		last_armored = armored
		return {"dealt": dealt, "armored": armored, "killed": health <= 0.0}


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func mouse_btn(pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return ev


func mouse_move() -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	return ev


func key_ev(code: Key, pressed: bool = true) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	return ev


func spawn_fake(parent: Node, list: Array, kind: StringName, pos: Vector3, facing: Vector3 = Vector3(0.0, 0.0, 1.0)) -> FakeEnemy:
	var e := FakeEnemy.new(kind, pos, facing)
	parent.add_child(e)
	list.append(e)
	return e


func clear_fakes(list: Array) -> void:
	for e in list:
		if is_instance_valid(e):
			e.queue_free()
	list.clear()


func run() -> void:
	var packed := load("res://scenes/prototype/arena.tscn") as PackedScene
	var arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)

	var player = arena.player
	var weapons = arena.weapons
	var enemies: Array = []

	# 1. Stationary world stroke while player moves + range/arena clamping
	weapons.reset_state()
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var anchor := Vector3(0.0, 0.0, -4.0)
	weapons.handle_event(mouse_btn(true), player, anchor)
	expect(weapons.ring_drawing and weapons.preview_points.size() == 1 and weapons.preview_points[0].distance_to(anchor) < 0.001, "Ring press anchors first world point")

	player.global_position = Vector3(5.0, 0.55, 3.0)
	weapons.handle_event(mouse_move(), player, Vector3(2.0, 0.0, -4.0))
	expect(weapons.preview_points[0].distance_to(anchor) < 0.001, "World stroke start stays stationary when player moves")

	weapons.reset_state()
	player.global_position = Vector3(0.0, 0.55, 0.0)
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -30.0))
	expect(is_equal_approx(weapons.preview_points[0].length(), float(Tuning.RING.range)), "Ring sample clamps to Tuning.RING.range from player")

	# 2. Tiny stroke ignored, redundant samples filtered, curves preserved, length capped at Tuning.RING.length
	weapons.reset_state()
	player.global_position = Vector3(0.0, 0.55, 0.0)
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -4.0))
	weapons.handle_event(mouse_move(), player, Vector3(0.05, 0.0, -4.0))
	expect(weapons.preview_points.size() == 1, "Redundant sample closer than sample_spacing is filtered")
	weapons.handle_event(mouse_move(), player, Vector3(0.35, 0.0, -4.0))
	weapons.handle_event(mouse_btn(false), player, Vector3(0.35, 0.0, -4.0))
	expect(weapons.ring_phase == "idle" and weapons.ring_points.is_empty(), "Tiny stroke shorter than minimum_length does not launch")

	weapons.reset_state()
	weapons.handle_event(mouse_btn(true), player, Vector3(-6.0, 0.0, -4.0))
	weapons.handle_event(mouse_move(), player, Vector3(6.0, 0.0, -4.0))
	weapons.handle_event(mouse_move(), player, Vector3(6.0, 0.0, 6.0))
	weapons.handle_event(mouse_move(), player, Vector3(-6.0, 0.0, 6.0))
	expect(is_equal_approx(weapons.preview_length, float(Tuning.RING.length)), "Ring stroke length caps at Tuning.RING.length")
	var count_at_cap: int = weapons.preview_points.size()
	var end_at_cap: Vector3 = weapons.preview_points[-1]
	weapons.handle_event(mouse_move(), player, Vector3(-6.0, 0.0, -4.0))
	expect(weapons.preview_points.size() == count_at_cap and weapons.preview_points[-1].distance_to(end_at_cap) < 0.001, "Ring stops adding points once stroke cap is reached")
	var has_corner := false
	for pt in weapons.preview_points:
		if pt.distance_to(Vector3(6.0, 0.0, -4.0)) < 0.25:
			has_corner = true
			break
	expect(has_corner, "Curved / corner stroke waypoints are preserved before the cap")

	# 3. Outbound harmless, swept stroke hit, once-per-launch, and moving return
	weapons.reset_state()
	clear_fakes(enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var outbound_e := spawn_fake(arena, enemies, &"target", Vector3(0.0, 0.0, -3.0))
	var stroke_e := spawn_fake(arena, enemies, &"target", Vector3(0.0, 0.0, -6.0))
	var return_e := spawn_fake(arena, enemies, &"target", Vector3(4.0, 0.0, -3.0))

	weapons.handle_event(mouse_btn(true), player, Vector3(-3.0, 0.0, -6.0))
	weapons.handle_event(mouse_move(), player, Vector3(3.0, 0.0, -6.0))
	weapons.handle_event(mouse_move(), player, Vector3(-3.0, 0.0, -6.0))
	weapons.handle_event(mouse_btn(false), player, Vector3(-3.0, 0.0, -6.0))
	expect(weapons.ring_phase == "outbound", "Valid stroke release launches ring into outbound phase")

	# Step through outbound to stroke start: outbound_e at (0,0,-3) is near outbound path; verify harmless
	weapons.step(0.15, player, Vector3.ZERO, enemies)
	expect(outbound_e.hit_count == 0 and is_equal_approx(outbound_e.health, 100.0), "Outbound ring travel deals no damage")

	# Large step traverses entire stroke (-3 -> +3 -> -3 across stroke_e twice): swept hit + once-per-launch
	weapons.step(0.50, player, Vector3.ZERO, enemies)
	expect(stroke_e.hit_count == 1 and is_equal_approx(stroke_e.health, 100.0 - float(Tuning.RING.damage)), "Swept stroke hits enemy and damages at most once per launch")
	expect(weapons.ring_phase == "return", "Ring enters return phase after completing stroke")

	# While returning, move player to (8, 0, 0) and verify no second launch while in flight + return homes to moving player harmlessly
	player.global_position = Vector3(8.0, 0.55, 0.0)
	weapons.handle_event(mouse_btn(true), player, Vector3(8.0, 0.0, -4.0))
	expect(not weapons.ring_drawing, "Second launch is blocked until active ring returns")

	for i in range(10):
		player.global_position += Vector3(0.2, 0.0, 0.1)
		weapons.step(0.08, player, Vector3.ZERO, enemies)
		if weapons.ring_phase == "idle":
			break
	expect(weapons.ring_phase == "idle" and Vector2(weapons.ring_pos.x - player.global_position.x, weapons.ring_pos.z - player.global_position.z).length() < 0.01, "Returning ring homes to moving player's current position")
	expect(return_e.hit_count == 0, "Returning ring deals no damage")

	# 4. Contact position accuracy: path behind Brute deals full damage, path in front is armored
	weapons.reset_state()
	clear_fakes(enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var brute_rear := spawn_fake(arena, enemies, &"brute", Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, 1.0))
	weapons.handle_event(mouse_btn(true), player, Vector3(-2.5, 0.0, -7.1))
	weapons.handle_event(mouse_move(), player, Vector3(2.5, 0.0, -7.1))
	weapons.handle_event(mouse_btn(false), player, Vector3(2.5, 0.0, -7.1))
	weapons.step(0.60, player, Vector3.ZERO, enemies)
	expect(brute_rear.hit_count == 1 and not brute_rear.last_armored and is_equal_approx(brute_rear.health, 180.0 - float(Tuning.RING.damage)), "Ring stroke behind Brute computes rear contact point and deals full unarmored damage")
	expect(brute_rear.last_contact.z < brute_rear.global_position.z - 0.5, "Ring rear contact point is behind Brute, not player position")

	weapons.reset_state()
	clear_fakes(enemies)
	var brute_front := spawn_fake(arena, enemies, &"brute", Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, 1.0))
	weapons.handle_event(mouse_btn(true), player, Vector3(-2.5, 0.0, -4.9))
	weapons.handle_event(mouse_move(), player, Vector3(2.5, 0.0, -4.9))
	weapons.handle_event(mouse_btn(false), player, Vector3(2.5, 0.0, -4.9))
	weapons.step(0.60, player, Vector3.ZERO, enemies)
	var expected_armored_dmg := float(Tuning.RING.damage) * float(Tuning.ARMOR.front_multiplier)
	expect(brute_front.hit_count == 1 and brute_front.last_armored and is_equal_approx(brute_front.health, 180.0 - expected_armored_dmg), "Ring stroke across Brute front triggers frontal armor reduction")

	# 5. Tool 2 (Flash / Beam): forgiving width, hits nearest enemy only, respects cooldown
	weapons.reset_state()
	clear_fakes(enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var near_e := spawn_fake(arena, enemies, &"target", Vector3(0.85, 0.0, -5.0)) # offset 0.85 <= beam.radius(0.35) + target.radius(0.70) = 1.05
	var far_e := spawn_fake(arena, enemies, &"target", Vector3(0.0, 0.0, -10.0))
	weapons.handle_event(key_ev(KEY_2), player, Vector3(0.0, 0.0, -10.0))
	expect(weapons.selected_tool == 2, "Key 2 selects Flash tool")
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -10.0))
	weapons.step(0.05, player, Vector3(0.0, 0.0, -10.0), enemies)
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -10.0))
	expect(near_e.hit_count == 1 and is_equal_approx(near_e.health, 100.0 - float(Tuning.BEAM.damage)), "Flash forgiving width hits off-center near enemy")
	expect(far_e.hit_count == 0 and is_equal_approx(far_e.health, 100.0), "Flash stops at first nearest enemy")

	# Click during cooldown does not fire
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -10.0))
	weapons.step(0.05, player, Vector3(0.0, 0.0, -10.0), enemies)
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -10.0))
	expect(near_e.hit_count == 1, "Flash cooldown prevents immediate re-fire")

	# Wait out remaining cooldown (0.25s total) and fire again
	weapons.step(0.20, player, Vector3(0.0, 0.0, -10.0), enemies)
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -10.0))
	weapons.step(0.01, player, Vector3(0.0, 0.0, -10.0), enemies)
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -10.0))
	expect(near_e.hit_count == 2, "Flash fires again once cooldown expires")

	# 6. Tool 3 (Cone): multi-enemy sector hit, real-delta consistency across step sizes & slow time
	weapons.reset_state()
	clear_fakes(enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	player.world_scale = 0.18
	var cone_e1 := spawn_fake(arena, enemies, &"target", Vector3(-1.0, 0.0, -3.5))
	var cone_e2 := spawn_fake(arena, enemies, &"target", Vector3(1.0, 0.0, -3.5))
	var outside_e := spawn_fake(arena, enemies, &"target", Vector3(4.5, 0.0, 0.0))
	weapons.handle_event(key_ev(KEY_3), player, Vector3(0.0, 0.0, -4.0))
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -4.0))
	for i in range(10):
		weapons.step(0.05, player, Vector3(0.0, 0.0, -4.0), enemies)
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -4.0))
	var dmg_ten_steps := 100.0 - cone_e1.health
	expect(is_equal_approx(dmg_ten_steps, float(Tuning.CONE.damage_per_second) * 0.5) and is_equal_approx(cone_e1.health, cone_e2.health), "Cone damages multiple enemies in sector using real delta")
	expect(outside_e.hit_count == 0, "Cone ignores enemies outside sector angle")

	# Compare with 2 steps of 0.25s
	clear_fakes(enemies)
	var cone_e3 := spawn_fake(arena, enemies, &"target", Vector3(0.0, 0.0, -3.5))
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -4.0))
	weapons.step(0.25, player, Vector3(0.0, 0.0, -4.0), enemies)
	weapons.step(0.25, player, Vector3(0.0, 0.0, -4.0), enemies)
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -4.0))
	var dmg_two_steps := 100.0 - cone_e3.health
	expect(is_equal_approx(dmg_ten_steps, dmg_two_steps), "Cone total damage is consistent across different delta sizes")

	# 7. Tool switch while held does not launch ring or fire new tool; cancel preserves travelling ring; reset clears all
	weapons.reset_state()
	clear_fakes(enemies)
	var switch_e := spawn_fake(arena, enemies, &"target", Vector3(0.0, 0.0, -3.5))
	weapons.handle_event(mouse_btn(true), player, Vector3(-2.0, 0.0, -3.5))
	weapons.handle_event(mouse_move(), player, Vector3(2.0, 0.0, -3.5))
	weapons.handle_event(key_ev(KEY_3), player, Vector3(0.0, 0.0, -3.5))
	expect(weapons.selected_tool == 3 and not weapons.ring_drawing and weapons.ring_phase == "idle" and not weapons.cone_active, "Switching tool while holding LMB cancels ring preview without launching or activating new tool")
	weapons.step(0.10, player, Vector3(0.0, 0.0, -3.5), enemies)
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -3.5))
	expect(switch_e.hit_count == 0 and weapons.ring_phase == "idle", "Releasing old held mouse press after tool switch does not fire")

	# Launch a ring, then call cancel_input() and switch tools while ring is travelling
	weapons.handle_event(key_ev(KEY_1), player, Vector3(-2.0, 0.0, -3.5))
	weapons.handle_event(mouse_btn(true), player, Vector3(-2.0, 0.0, -3.5))
	weapons.handle_event(mouse_move(), player, Vector3(2.0, 0.0, -3.5))
	weapons.handle_event(mouse_btn(false), player, Vector3(2.0, 0.0, -3.5))
	expect(weapons.ring_phase == "outbound", "Ring is in flight before cancel_input")
	weapons.cancel_input()
	weapons.handle_event(key_ev(KEY_2), player, Vector3(0.0, 0.0, -3.5))
	expect(weapons.selected_tool == 2 and weapons.ring_phase != "idle", "cancel_input and tool switch preserve an already travelling ring")
	weapons.step(0.35, player, Vector3(0.0, 0.0, -3.5), enemies)
	expect(switch_e.hit_count == 1, "Travelling ring still damages enemies along stroke while switched to another tool")

	weapons.reset_state()
	expect(weapons.selected_tool == 1 and weapons.ring_phase == "idle" and weapons.ring_points.is_empty() and not weapons.cone_active and is_equal_approx(weapons.beam_cooldown, 0.0), "reset_state clears active ring, trails, cone, cooldowns, and restores tool 1")

	clear_fakes(enemies)
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
