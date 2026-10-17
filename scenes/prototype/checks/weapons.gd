extends SceneTree

const Tuning = preload("res://scenes/prototype/tuning.gd")

var failures: Array[String] = []
var checks: int = 0


class FakeEnemy extends Node3D:
	const TuningRef = preload("res://scenes/prototype/tuning.gd")
	var rewind_id: int = 0
	var kind: StringName = &"target"
	var radius: float = 0.7
	var health: float = 100.0
	var facing: Vector3 = Vector3(0.0, 0.0, 1.0)
	var hit_count: int = 0
	var last_contact: Vector3 = Vector3.ZERO
	var last_armored: bool = false
	var control_count: int = 0
	var strong_control_count: int = 0
	var sustained_control_count: int = 0
	var last_control_dir: Vector3 = Vector3.ZERO
	var last_control_impulse: float = 0.0
	var last_control_stagger: float = 0.0
	var total_control_impulse: float = 0.0

	func _init(p_kind: StringName, pos: Vector3, p_facing: Vector3 = Vector3(0.0, 0.0, 1.0), p_rewind_id: int = 0) -> void:
		rewind_id = p_rewind_id
		kind = p_kind
		var cfg: Dictionary = TuningRef.ENEMIES.get(String(p_kind), TuningRef.ENEMIES["target"])
		health = float(cfg["health"])
		radius = float(cfg["radius"])
		position = pos
		var f2 := Vector2(p_facing.x, p_facing.z)
		facing = Vector3(f2.x, 0.0, f2.y).normalized() if f2.length_squared() > 1e-6 else Vector3(0.0, 0.0, 1.0)

	func combat_id() -> int:
		return rewind_id if rewind_id > 0 else get_instance_id()

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

	func apply_control(direction_xz: Vector3, impulse: float, stagger_seconds: float) -> void:
		if health <= 0.0 or impulse <= 0.0:
			return
		control_count += 1
		if stagger_seconds > 0.0:
			strong_control_count += 1
		else:
			sustained_control_count += 1
		last_control_dir = direction_xz
		last_control_impulse = impulse
		last_control_stagger = stagger_seconds
		total_control_impulse += impulse


var _next_fake_id: int = 1


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


func spawn_fake(parent: Node, list: Array, kind: StringName, pos: Vector3, facing: Vector3 = Vector3(0.0, 0.0, 1.0), custom_id: int = 0) -> FakeEnemy:
	var cid := custom_id if custom_id > 0 else _next_fake_id
	if custom_id <= 0:
		_next_fake_id += 1
	var e := FakeEnemy.new(kind, pos, facing, cid)
	parent.add_child(e)
	list.append(e)
	return e


func clear_fakes(list: Array) -> void:
	for e in list:
		if is_instance_valid(e):
			e.queue_free()
	list.clear()


func reset_section(arena: Node, weapons: Node, enemies: Array) -> void:
	clear_fakes(enemies)
	arena.equipment.reset_state()
	weapons.reset_state()


func has_object_ref(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal:
		return true
	if value is Array:
		var arr: Array = value
		for item in arr:
			if has_object_ref(item):
				return true
	elif value is Dictionary:
		var dict: Dictionary = value
		for k in dict.keys():
			if has_object_ref(k) or has_object_ref(dict[k]):
				return true
	return false


func run() -> void:
	var packed := load("res://scenes/prototype/arena.tscn") as PackedScene
	var arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	arena.director.clear()

	var player = arena.player
	var weapons = arena.weapons
	var equipment = arena.equipment
	var enemies: Array = []

	var target_max_hp := float(Tuning.ENEMIES.target.health)
	var brute_max_hp := float(Tuning.ENEMIES.brute.health)

	# 0. Round D: TOOL_IDS & Key 4 (Clock selection with no LMB action)
	reset_section(arena, weapons, enemies)
	expect(weapons.TOOL_IDS == [&"ring", &"beam", &"cone", &"clock"], "weapons exposes TOOL_IDS for ring, beam, cone, clock")
	weapons.handle_event(key_ev(KEY_4), player, Vector3(0.0, 0.0, -4.0))
	expect(weapons.selected_tool == 4, "Key 4 selects Clock (tool 4)")
	var clock_before := float(equipment.remaining(&"clock"))
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -4.0))
	weapons.step(0.25, player, Vector3(0.0, 0.0, -4.0), enemies)
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -4.0))
	expect(not weapons.ring_drawing and not weapons.beam_charging and not weapons.cone_active and is_equal_approx(float(equipment.remaining(&"clock")), clock_before), "Clock has no left-click weapon action or wear")

	# 1. Stationary world stroke while player moves + range/arena clamping + tiny stroke rejection + length cap
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var anchor := Vector3(0.0, 0.0, -4.0)
	weapons.handle_event(mouse_btn(true), player, anchor)
	expect(weapons.ring_drawing and weapons.preview_points.size() == 1 and weapons.preview_points[0].distance_to(anchor) < 0.001, "Ring press anchors first world point")

	player.global_position = Vector3(5.0, 0.55, 3.0)
	weapons.handle_event(mouse_move(), player, Vector3(2.0, 0.0, -4.0))
	expect(weapons.preview_points[0].distance_to(anchor) < 0.001, "World stroke start stays stationary when player moves")

	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -30.0))
	expect(is_equal_approx(weapons.preview_points[0].length(), float(Tuning.RING.range)), "Ring sample clamps to Tuning.RING.range from player")

	reset_section(arena, weapons, enemies)
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -4.0))
	weapons.handle_event(mouse_move(), player, Vector3(0.05, 0.0, -4.0))
	expect(weapons.preview_points.size() == 1, "Redundant sample closer than sample_spacing is filtered")
	weapons.handle_event(mouse_move(), player, Vector3(0.35, 0.0, -4.0))
	weapons.handle_event(mouse_btn(false), player, Vector3(0.35, 0.0, -4.0))
	expect(weapons.ring_phase == "idle" and weapons.ring_points.is_empty() and is_equal_approx(float(equipment.remaining(&"ring")), float(equipment.capacity(&"ring"))), "Tiny stroke shorter than minimum_length does not launch or spend wear")

	reset_section(arena, weapons, enemies)
	weapons.handle_event(mouse_btn(true), player, Vector3(-6.0, 0.0, -4.0))
	weapons.handle_event(mouse_move(), player, Vector3(6.0, 0.0, -4.0))
	weapons.handle_event(mouse_move(), player, Vector3(6.0, 0.0, 6.0))
	weapons.handle_event(mouse_move(), player, Vector3(-6.0, 0.0, 6.0))
	expect(is_equal_approx(weapons.preview_length, float(Tuning.RING.length)), "Ring stroke length caps at Tuning.RING.length")

	# 2. Round D Ring: Outbound arcs ABOVE cover harmlessly; cutting stroke stops at cover; blocked preview split; stable combat_id
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(-5.0, 0.55, -1.0)
	var outbound_e := spawn_fake(arena, enemies, &"target", Vector3(-5.0, 0.0, -2.0))
	var behind_cover_e := spawn_fake(arena, enemies, &"target", Vector3(-5.0, 0.0, -7.5), Vector3(0.0, 0.0, 1.0), 77)

	# Draw stroke behind cover box Rect2(-6, -6, 2, 3): outbound from (-5,0,-1) to (-5.8,0,-7.5) crosses cover
	weapons.handle_event(mouse_btn(true), player, Vector3(-5.8, 0.0, -7.5))
	weapons.handle_event(mouse_move(), player, Vector3(-4.2, 0.0, -7.5))
	expect(not weapons.preview_blocked, "Stroke drawn entirely behind cover is not marked blocked")
	weapons.handle_event(mouse_btn(false), player, Vector3(-4.2, 0.0, -7.5))
	expect(weapons.ring_phase == "outbound" and is_equal_approx(float(equipment.remaining(&"ring")), float(equipment.capacity(&"ring")) - 1.0), "Ring launches into outbound phase and spends 1 unit")

	# Step to midpoint of outbound flight over cover box (distance ~6.55m, speed 24 -> ~0.136s is midpoint)
	weapons.step(0.135, player, Vector3.ZERO, enemies)
	expect(weapons.ring_phase == "outbound" and weapons.ring_pos.y > 2.2, "Outbound ring physically arcs above 2.2m cover height")
	expect(outbound_e.hit_count == 0, "Outbound arc deals no damage to enemies underneath")

	# Finish outbound and enter stroke, hitting behind_cover_e (combat_id = 77)
	weapons.step(0.18, player, Vector3.ZERO, enemies)
	expect(behind_cover_e.hit_count == 1 and is_equal_approx(behind_cover_e.health, target_max_hp - float(Tuning.RING.damage)), "Outbound ring lands behind cover and cutting stroke hits enemy behind cover")

	# Simulate rewind/recreate of enemy node with same stable combat_id = 77 before stroke finishes a loop back
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var e_first := spawn_fake(arena, enemies, &"target", Vector3(0.0, 0.0, -5.0), Vector3(0.0, 0.0, 1.0), 88)
	weapons.handle_event(mouse_btn(true), player, Vector3(-3.0, 0.0, -5.0))
	weapons.handle_event(mouse_move(), player, Vector3(3.0, 0.0, -5.0))
	weapons.handle_event(mouse_move(), player, Vector3(-3.0, 0.0, -5.0))
	weapons.handle_event(mouse_btn(false), player, Vector3(-3.0, 0.0, -5.0))
	# Advance through outbound + first pass of stroke (-3 -> +3)
	weapons.step(0.38, player, Vector3.ZERO, enemies)
	expect(e_first.hit_count == 1 and weapons.ring_hit_ids.has(88), "Ring records enemy stable combat_id on first pass")
	# Replace node instance with a brand new node sharing combat_id = 88 before return pass (+3 -> -3)
	clear_fakes(enemies)
	var e_recreated := spawn_fake(arena, enemies, &"target", Vector3(0.0, 0.0, -5.0), Vector3(0.0, 0.0, 1.0), 88)
	weapons.step(0.30, player, Vector3.ZERO, enemies)
	expect(e_recreated.hit_count == 0, "Stable combat_id prevents double-hit even when enemy node instance is recreated")

	# Preview blocked stroke portion & cutting stroke stopping at cover
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(-2.0, 0.55, -4.5)
	var before_wall_e := spawn_fake(arena, enemies, &"target", Vector3(-3.0, 0.0, -4.5))
	var after_wall_e := spawn_fake(arena, enemies, &"target", Vector3(-7.2, 0.0, -4.5))
	weapons.handle_event(mouse_btn(true), player, Vector3(-2.5, 0.0, -4.5))
	weapons.handle_event(mouse_move(), player, Vector3(-7.5, 0.0, -4.5))
	expect(weapons.preview_blocked and is_equal_approx(weapons.preview_cutoff_point.x, -3.6) and weapons.preview_blocked_points.size() >= 2, "Preview detects stroke cutting into cover and splits unblocked vs blocked points")
	weapons.handle_event(mouse_btn(false), player, Vector3(-7.5, 0.0, -4.5))
	weapons.step(0.80, player, Vector3.ZERO, enemies)
	expect(before_wall_e.hit_count == 1 and after_wall_e.hit_count == 0 and weapons.ring_phase == "idle", "Cutting stroke hits enemy before cover, stops at cover wall, and returns harmlessly")

	# Contact position accuracy (Brute rear unarmored vs front armored)
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var brute_rear := spawn_fake(arena, enemies, &"brute", Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, 1.0))
	weapons.handle_event(mouse_btn(true), player, Vector3(-2.5, 0.0, -7.1))
	weapons.handle_event(mouse_move(), player, Vector3(2.5, 0.0, -7.1))
	weapons.handle_event(mouse_btn(false), player, Vector3(2.5, 0.0, -7.1))
	weapons.step(0.60, player, Vector3.ZERO, enemies)
	expect(brute_rear.hit_count == 1 and not brute_rear.last_armored and is_equal_approx(brute_rear.health, brute_max_hp - float(Tuning.RING.damage)), "Ring stroke behind Brute deals full unarmored damage")

	# 3. Round D Tool 2 (Charged Traveling Flash): tap vs full charge, long range (~35), slow travel, swept moving hit, cover stop, cancellation & bounds
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var tap_target := spawn_fake(arena, enemies, &"brute", Vector3(0.0, 0.0, -8.0), Vector3(0.0, 0.0, -1.0)) # Facing away so rear is unarmored
	weapons.handle_event(key_ev(KEY_2), player, Vector3(0.0, 0.0, -8.0))
	expect(weapons.selected_tool == 2, "Key 2 selects Flash tool")

	# Press starts charging without firing or spending ammo
	var beam_cap := float(equipment.capacity(&"beam"))
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -8.0))
	expect(weapons.beam_charging and weapons.beam_pulses.is_empty() and is_equal_approx(float(equipment.remaining(&"beam")), beam_cap), "Flash press begins charging without instant shot or ammo spend")

	# Release immediately (tap shot): launches weak pulse (~30 dmg) and spends 1 unit
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -8.0))
	expect(not weapons.beam_charging and weapons.beam_pulses.size() == 1 and is_equal_approx(float(equipment.remaining(&"beam")), beam_cap - 1.0), "Tap release launches traveling Flash pulse and spends 1 unit")
	weapons.step(0.30, player, Vector3(0.0, 0.0, -8.0), enemies)
	expect(tap_target.hit_count == 1 and is_equal_approx(brute_max_hp - tap_target.health, weapons._beam_min_damage()), "Quick tap Flash pulse deals minimum damage (~30)")

	# Wait cooldown, then charge for full duration (~0.9 real seconds) while world_delta is slowed
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var far_charged_e := spawn_fake(arena, enemies, &"brute", Vector3(0.0, 0.0, -28.0), Vector3(0.0, 0.0, -1.0)) # 28m distance tests ~35m long range
	weapons.select_tool(2)
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -28.0))
	var charge_dur: float = weapons._beam_charge_duration()
	weapons.step(charge_dur * 0.5, player, Vector3(0.0, 0.0, -28.0), enemies, charge_dur * 0.5 * 0.18)
	expect(is_equal_approx(weapons.beam_charge, 0.5), "Flash charge progresses in real delta even when world_delta is slowed")
	weapons.step(charge_dur * 0.6, player, Vector3(0.0, 0.0, -28.0), enemies, charge_dur * 0.6 * 0.18)
	expect(is_equal_approx(weapons.beam_charge, 1.0), "Flash charge clamps at 1.0 after full real charge duration")
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -28.0))
	expect(weapons.beam_pulses.size() == 1 and is_equal_approx(weapons.beam_charge, 0.0), "Releasing charged Flash launches pulse and resets beam_charge")

	# Step with slow world_delta: pulse travels slowly in world time, then accelerates when normal world_delta resumes
	weapons.step(0.20, player, Vector3(0.0, 0.0, -28.0), enemies, 0.20 * 0.18)
	var slow_z: float = float(weapons.beam_pulses[0]["pos"].z)
	expect(far_charged_e.hit_count == 0 and slow_z > -4.0, "Flash projectile flight uses world_delta during slow time")
	weapons.step(0.80, player, Vector3(0.0, 0.0, -28.0), enemies, 0.80)
	expect(far_charged_e.hit_count == 1 and is_equal_approx(brute_max_hp - far_charged_e.health, weapons._beam_max_damage()), "Fully charged Flash pulse reaches 28m target and deals max damage (~100)")

	# Swept moving hit & stops at first enemy / nearest cover
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var moving_near_e := spawn_fake(arena, enemies, &"target", Vector3(0.75, 0.0, -6.0)) # Forgiving width
	var behind_e := spawn_fake(arena, enemies, &"target", Vector3(0.0, 0.0, -12.0))
	weapons.select_tool(2)
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -12.0))
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -12.0))
	weapons.step(0.40, player, Vector3(0.0, 0.0, -12.0), enemies)
	expect(moving_near_e.hit_count == 1 and behind_e.hit_count == 0 and weapons.beam_pulses.is_empty(), "Traveling Flash pulse hits off-center first enemy and stops without piercing")

	# Cover blocks traveling Flash pulse before enemy behind cover
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(-5.0, 0.55, -1.0)
	var behind_wall_e := spawn_fake(arena, enemies, &"target", Vector3(-5.0, 0.0, -7.5))
	weapons.select_tool(2)
	weapons.handle_event(mouse_btn(true), player, Vector3(-5.0, 0.0, -8.0))
	weapons.handle_event(mouse_btn(false), player, Vector3(-5.0, 0.0, -8.0))
	weapons.step(0.30, player, Vector3(-5.0, 0.0, -8.0), enemies)
	expect(behind_wall_e.hit_count == 0 and weapons.beam_pulses.is_empty() and is_equal_approx(weapons.beam_end.z, -3.0), "Traveling Flash pulse stops at cover wall and does not hit enemy behind cover")

	# Cancelled charge spends zero capacity and release after tool switch / popup does not fire
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var cancel_e := spawn_fake(arena, enemies, &"target", Vector3(0.0, 0.0, -5.0))
	weapons.select_tool(2)
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -5.0))
	weapons.step(0.50, player, Vector3(0.0, 0.0, -5.0), enemies)
	weapons.handle_event(key_ev(KEY_1), player, Vector3(0.0, 0.0, -5.0))
	expect(not weapons.beam_charging and is_equal_approx(weapons.beam_charge, 0.0) and is_equal_approx(float(equipment.remaining(&"beam")), float(equipment.capacity(&"beam"))), "Switching tools while charging Flash cancels charge with zero wear")
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -5.0))
	weapons.step(0.20, player, Vector3(0.0, 0.0, -5.0), enemies)
	expect(cancel_e.hit_count == 0 and weapons.beam_pulses.is_empty(), "Releasing LMB after charge cancellation does not fire")

	# Bounded active pulses (max 8)
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	weapons.select_tool(2)
	var max_p: int = weapons._beam_max_pulses()
	for i in range(max_p + 2):
		weapons.beam_cooldown = 0.0
		weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -15.0))
		weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -15.0))
	expect(weapons.beam_pulses.size() == max_p, "Active Flash pulses are bounded at max_pulses (%d)" % max_p)

	# 4. Round D Tool 3 (Cone): repeating pulses while held, world_delta cadence, edge-volume inclusion, LOS, affordable pulse limit, no rapid tap reset
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	# Edge enemy: center angle atan2(2.6, 3.0) = 0.714 rad > half_angle(0.65), but brute radius 1.0 gives asin(1.0 / 3.97) = 0.255 rad overlap
	var edge_brute := spawn_fake(arena, enemies, &"brute", Vector3(2.6, 0.0, -3.0))
	edge_brute.health = 500.0
	var far_outside_e := spawn_fake(arena, enemies, &"target", Vector3(4.5, 0.0, 0.0))
	var pulse_interval: float = weapons._cone_pulse_interval()
	var pulse_cost: float = weapons._cone_pulse_cost()
	var pulse_imp: float = weapons._cone_pulse_impulse()
	var pulse_stg: float = weapons._cone_pulse_stagger()
	var cone_cap := float(equipment.capacity(&"cone"))

	weapons.handle_event(key_ev(KEY_3), player, Vector3(0.0, 0.0, -4.0))
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -4.0))
	weapons.step(0.10, player, Vector3(0.0, 0.0, -4.0), enemies, 0.10)
	expect(edge_brute.strong_control_count == 1 and far_outside_e.control_count == 0, "Cone includes enemy whose volume overlaps cone edge and triggers initial pulse")
	expect(is_equal_approx(edge_brute.last_control_impulse, pulse_imp) and is_equal_approx(edge_brute.last_control_stagger, pulse_stg), "Cone pulse applies strong impulse (~22) and stagger (~0.85)")
	expect(is_equal_approx(float(equipment.remaining(&"cone")), cone_cap - 0.10 - pulse_cost), "Cone pulse spends real delta plus pulse_cost")

	# Hold Cone in slow time (real delta = 1.2s, world_delta = 1.2 * 0.18 = 0.216s < pulse_interval): no second strong pulse yet
	weapons.step(1.20, player, Vector3(0.0, 0.0, -4.0), enemies, 1.20 * 0.18)
	expect(edge_brute.strong_control_count == 1, "Cone pulse cadence uses world_delta (slow time does not amplify pulse rate)")

	# Advance remaining world time to reach pulse_interval while still holding LMB: second strong pulse fires!
	var rem_world_to_pulse := pulse_interval - 0.10 - (1.20 * 0.18) + 0.02
	weapons.step(rem_world_to_pulse, player, Vector3(0.0, 0.0, -4.0), enemies, rem_world_to_pulse)
	expect(edge_brute.strong_control_count == 2, "Holding Cone repeats strong shove/stagger once pulse_interval world seconds elapse")

	# Release and rapidly re-tap LMB while pulse cooldown > 0: no rapid tap reset
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -4.0))
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -4.0))
	weapons.step(0.10, player, Vector3(0.0, 0.0, -4.0), enemies, 0.10)
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -4.0))
	expect(edge_brute.strong_control_count == 2, "Rapid tap release/re-press does not reset Cone pulse cooldown or trigger extra pulse")

	# Limit pulse to affordable capacity & no empty-tool shove
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var afford_e := spawn_fake(arena, enemies, &"target", Vector3(0.0, 0.0, -3.0))
	# Leave 0.10s for tick + 50% of pulse_cost
	equipment.spend(&"cone", float(equipment.capacity(&"cone")) - (0.10 + pulse_cost * 0.5))
	weapons.select_tool(3)
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -3.0))
	weapons.step(0.10, player, Vector3(0.0, 0.0, -3.0), enemies, 0.10)
	expect(afford_e.strong_control_count == 1 and is_equal_approx(afford_e.last_control_impulse, pulse_imp * 0.5) and is_equal_approx(afford_e.last_control_stagger, pulse_stg * 0.5), "Cone scales pulse impulse and stagger to affordable remaining capacity")
	expect(is_equal_approx(float(equipment.remaining(&"cone")), 0.0) and not weapons.cone_active, "Cone stops when capacity reaches zero")

	# Empty cone produces no shove or damage
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -3.0))
	weapons.step(0.20, player, Vector3(0.0, 0.0, -3.0), enemies, 0.20)
	expect(afford_e.strong_control_count == 1 and not weapons.cone_active and "Repair" in weapons.last_feedback, "Empty Cone blocks activation and produces no empty-tool shove")

	# Cone LOS occlusion
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(-5.0, 0.55, -1.2)
	var cone_vis_e := spawn_fake(arena, enemies, &"swarmer", Vector3(-5.0, 0.0, -2.3))
	var cone_occ_e := spawn_fake(arena, enemies, &"swarmer", Vector3(-5.0, 0.0, -5.8))
	weapons.select_tool(3)
	weapons.handle_event(mouse_btn(true), player, Vector3(-5.0, 0.0, -6.0))
	weapons.step(0.10, player, Vector3(-5.0, 0.0, -6.0), enemies, 0.10)
	weapons.handle_event(mouse_btn(false), player, Vector3(-5.0, 0.0, -6.0))
	expect(cone_vis_e.hit_count == 1 and cone_vis_e.control_count == 1 and cone_occ_e.hit_count == 0 and cone_occ_e.control_count == 0, "Cone preserves cover LOS occlusion")

	# 5. Round D Snapshot Contract: capture_state() / restore_state() value purity, active flights/pulses round-trip, held gesture cancellation
	reset_section(arena, weapons, enemies)
	player.global_position = Vector3(0.0, 0.55, 0.0)
	var snap_enemy := spawn_fake(arena, enemies, &"brute", Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, -1.0), 303)

	# Launch a Ring and a traveling Flash pulse, then begin holding a new Flash charge
	weapons.select_tool(1)
	weapons.handle_event(mouse_btn(true), player, Vector3(-3.0, 0.0, -10.0))
	weapons.handle_event(mouse_move(), player, Vector3(3.0, 0.0, -10.0))
	weapons.handle_event(mouse_btn(false), player, Vector3(3.0, 0.0, -10.0))
	weapons.step(0.10, player, Vector3(0.0, 0.0, -10.0), enemies, 0.10)

	weapons.select_tool(2)
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -10.0))
	weapons.step(0.45, player, Vector3(0.0, 0.0, -10.0), enemies, 0.05)
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -10.0))
	weapons.beam_cooldown = 0.0
	weapons.handle_event(mouse_btn(true), player, Vector3(0.0, 0.0, -10.0))
	weapons.step(0.30, player, Vector3(0.0, 0.0, -10.0), enemies, 0.05)
	expect(weapons.ring_phase != "idle" and weapons.beam_pulses.size() == 1 and weapons.beam_charging, "Pre-snapshot state has active ring, active Flash pulse, and held Flash charge")

	var snapshot: Dictionary = weapons.capture_state()
	expect(not has_object_ref(snapshot), "capture_state contains pure value data with no Object/Node/Callable references")
	var snap_ring_pos: Vector3 = snapshot["ring_pos"]
	var snap_pulse_pos: Vector3 = snapshot["beam_pulses"][0]["pos"]

	# Advance simulation until both ring and pulse finish and hit snap_enemy
	weapons.step(1.50, player, Vector3(0.0, 0.0, -10.0), enemies, 1.50)
	expect(weapons.ring_phase == "idle" and weapons.beam_pulses.is_empty() and snap_enemy.hit_count == 2, "Advancing after snapshot completes ring and Flash pulse hits")

	# Restore snapshot: active ring and pulse are back in flight, held charge is cancelled, releasing LMB does not fire
	var hp_after_restore_test := snap_enemy.health
	weapons.restore_state(snapshot)
	expect(weapons.ring_phase != "idle" and weapons.ring_pos.distance_to(snap_ring_pos) < 0.001, "restore_state restores active ring flight position and phase")
	expect(weapons.beam_pulses.size() == 1 and Vector3(weapons.beam_pulses[0]["pos"]).distance_to(snap_pulse_pos) < 0.001, "restore_state restores active Flash projectile state")
	expect(not weapons.beam_charging and is_equal_approx(weapons.beam_charge, 0.0) and not weapons.ring_drawing and not weapons.cone_active, "restore_state cancels held gestures")

	# Releasing the pre-restore held mouse button must not launch a second Flash pulse
	weapons.handle_event(mouse_btn(false), player, Vector3(0.0, 0.0, -10.0))
	expect(weapons.beam_pulses.size() == 1, "Releasing held LMB after restore_state does not fire a shot")

	# Advancing from restored state completes the restored ring and pulse normally
	weapons.step(1.50, player, Vector3(0.0, 0.0, -10.0), enemies, 1.50)
	expect(snap_enemy.health < hp_after_restore_test and weapons.ring_phase == "idle" and weapons.beam_pulses.is_empty(), "Restored in-flight ring and Flash pulse resume and hit target")

	clear_fakes(enemies)
	arena.queue_free()
	await process_frame
	# Allow the audio server to release generated playback after scene removal.
	await create_timer(0.10).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
