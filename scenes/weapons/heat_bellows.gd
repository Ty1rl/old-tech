class_name HeatBellows
extends WeaponComponent
## Real-time wear; world-time heat, displacement and pulse cadence.
@export var settings: HeatBellowsSettings = preload("res://scenes/weapons/settings/heat_bellows.tres")
var active := false
var origin := Vector3.ZERO
var forward := Vector2.UP
var pulse_cooldown := 0.0
var fresh_press := false

func press(source: Vector3, aim: Vector3) -> void:
	if not _can_use_tool(&"cone"):
		active = false
		fresh_press = false
		last_feedback = "Cone empty - press E to repair"
		return
	active = true
	fresh_press = true
	aim_at(source, aim)
	last_feedback = "Cone active"

func release() -> void:
	if active:
		active = false
		fresh_press = false
		last_feedback = "Cone released"

func aim_at(origin_world: Vector3, aim_world: Vector3) -> void:
	origin = Vector3(origin_world.x, 0.0, origin_world.z)
	forward = _aim_dir_xz(origin_world, aim_world)

func step(delta: float, w_delta: float, source: Vector3, muzzle: Vector3, enemies: Array) -> void:
	if not active:
		pulse_cooldown = maxf(0, pulse_cooldown - maxf(0, w_delta))
		return
	if delta <= 0.0:
		return
	if not _can_use_tool(&"cone"):
		active = false
		fresh_press = false
		if w_delta > 0.0:
			pulse_cooldown = maxf(0.0, pulse_cooldown - w_delta)
		last_feedback = "Cone empty - press E to repair"
		return

	# Continuous wear uses REAL delta; continuous damage & pulse cadence use WORLD delta.
	var actual_real_dt := _spend_tool(&"cone", delta)
	if actual_real_dt <= 0.0:
		active = false
		fresh_press = false
		if w_delta > 0.0:
			pulse_cooldown = maxf(0.0, pulse_cooldown - w_delta)
		last_feedback = "Cone empty - press E to repair"
		return

	var afford_fraction := clampf(actual_real_dt / delta, 0.0, 1.0)
	var actual_world_dt := maxf(0.0, w_delta) * afford_fraction

	var do_burst := false
	var burst_scale := 0.0
	var pulse_interval := settings.pulse_interval
	var pulse_cost := settings.pulse_cost

	if fresh_press:
		fresh_press = false
		if pulse_cooldown <= 1e-6 and w_delta > 0.0:
			var pulse_spent := _spend_tool(&"cone", pulse_cost)
			if pulse_spent > 1e-6:
				do_burst = true
				burst_scale = clampf(pulse_spent / pulse_cost, 0.0, 1.0)
				pulse_cooldown = maxf(0.0, pulse_interval - actual_world_dt)
		else:
			pulse_cooldown -= actual_world_dt
			if pulse_cooldown <= 1e-6 and w_delta > 0.0:
				var pulse_spent := _spend_tool(&"cone", pulse_cost)
				if pulse_spent > 1e-6:
					do_burst = true
					burst_scale = clampf(pulse_spent / pulse_cost, 0.0, 1.0)
					pulse_cooldown = maxf(0.0, pulse_cooldown + pulse_interval)
				else:
					pulse_cooldown = 0.0
	else:
		pulse_cooldown -= actual_world_dt
		if pulse_cooldown <= 1e-6 and w_delta > 0.0:
			var pulse_spent := _spend_tool(&"cone", pulse_cost)
			if pulse_spent > 1e-6:
				do_burst = true
				burst_scale = clampf(pulse_spent / pulse_cost, 0.0, 1.0)
				pulse_cooldown = maxf(0.0, pulse_cooldown + pulse_interval)
			else:
				pulse_cooldown = 0.0

	if do_burst:
		combat_event.emit(&"cone_pulse", muzzle, burst_scale)
	var p_xz := Vector2(source.x, source.z)
	var origin_3d := Vector3(p_xz.x, 0.0, p_xz.y)
	var max_r := (settings.range)
	var half_ang := (settings.half_angle)
	var amount := (settings.damage_per_second) * actual_world_dt
	var burst_impulse := settings.pulse_impulse * burst_scale
	var burst_stagger := settings.pulse_stagger * burst_scale
	var sustained_impulse := settings.sustained_push * actual_world_dt
	var hit_any := false
	var any_armored := false
	var total_dealt := 0.0

	for enemy in enemies:
		if not _is_live_enemy(enemy):
			continue
		var enemy_node := enemy as Node3D
		var c := Vector2(enemy_node.global_position.x, enemy_node.global_position.z)
		var r_enemy: float = float(enemy_node.radius)
		var to_enemy := c - p_xz
		var dist := to_enemy.length()
		if dist - r_enemy > max_r:
			continue
		if dist > 1e-5:
			var ang := absf(forward.angle_to(to_enemy))
			var edge_allowance: float = asin(clampf(r_enemy / dist, 0.0, 1.0)) if dist > r_enemy else PI
			if ang > half_ang + edge_allowance:
				continue
		var dir_from_enemy := (p_xz - c).normalized() if dist > 1e-5 else -forward
		var contact_xz := c + dir_from_enemy * r_enemy
		var contact_world := Vector3(contact_xz.x, 0.0, contact_xz.y)
		var enemy_world := Vector3(c.x, 0.0, c.y)
		if cover != null:
			var los: Dictionary = cover.clip_segment(origin_3d, enemy_world, 0.0)
			if bool(los["blocked"]):
				continue

		var push_2d := to_enemy.normalized() if dist > 1e-5 else forward
		var push_dir := Vector3(push_2d.x, 0.0, push_2d.y)
		if do_burst and burst_impulse > 0.0:
			enemy_node.apply_control(push_dir, burst_impulse, burst_stagger)
		elif sustained_impulse > 0.0:
			enemy_node.apply_control(push_dir, sustained_impulse, 0.0)

		if amount > 0.0:
			var res := _attack_enemy(enemy_node, &"cone", amount, contact_world,
				{"segment_start": origin_3d, "segment_end": enemy_world, "radius": 0.0, "dt": actual_world_dt})
			var dealt := float(res.get("dealt", 0.0))
			if dealt > 0.0:
				hit_any = true
				total_dealt += dealt
				if bool(res.get("armored", false)):
					any_armored = true

	if hit_any:
		var burst_tag := " PULSE" if do_burst else ""
		var armor_tag := " (ARMORED)" if any_armored else ""
		last_feedback = "Cone%s %.1f dmg%s" % [burst_tag, total_dealt, armor_tag]
	elif do_burst:
		last_feedback = "Cone pulse"

	if not _can_use_tool(&"cone"):
		active = false
		if not hit_any:
			last_feedback = "Cone empty - press E to repair"

func cancel_input() -> void:
	active = false
	fresh_press = false

func reset_state() -> void:
	cancel_input()
	origin = Vector3.ZERO
	forward = Vector2.UP
	pulse_cooldown = 0

func capture_state() -> Dictionary:
	return {"origin": origin, "forward": forward, "pulse_cooldown": pulse_cooldown}

func restore_state(data: Dictionary) -> void:
	cancel_input()
	origin = data.get("origin", Vector3.ZERO)
	forward = data.get("forward", Vector2.UP)
	pulse_cooldown = maxf(0, float(data.get("pulse_cooldown", 0)))
