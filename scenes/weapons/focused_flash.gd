class_name FocusedFlash
extends WeaponComponent
## Real-time charging/cooldown; straight, cover-clipped world-time projectiles.
@export var settings: FocusedFlashSettings = preload("res://scenes/weapons/settings/focused_flash.tres")
var charging := false
var charge_time := 0.0
var charge := 0.0
var cooldown := 0.0
var flash_timer := 0.0
var start_point := Vector3.ZERO
var end_point := Vector3.ZERO
var visual_origin := Vector3.ZERO
var flash_charge := 0.0
var pulses: Array[Dictionary] = []

func press() -> void:
	if not _can_use_tool(&"beam", 1.0):
		charging = false
		charge_time = 0.0
		charge = 0.0
		last_feedback = "Flash empty - press E to repair"
		return
	if cooldown > 0.0:
		last_feedback = "Flash cooling (%.2fs)" % cooldown
		return
	if pulses.size() >= settings.max_pulses:
		last_feedback = "Flash max pulses active (%d)" % settings.max_pulses
		return
	charging = true
	charge_time = 0.0
	charge = 0.0
	last_feedback = "Charging Flash"

func release(origin: Vector3, aim: Vector3, muzzle: Vector3) -> void:
	if not charging:
		return
	var charge_frac := clampf(charge_time / maxf(0.05, settings.charge_time), 0.0, 1.0)
	charging = false
	charge_time = 0.0
	charge = 0.0
	if not _can_use_tool(&"beam", 1.0):
		last_feedback = "Flash empty - press E to repair"
		return
	if pulses.size() >= settings.max_pulses:
		last_feedback = "Flash max pulses active (%d)" % settings.max_pulses
		return
	_spend_tool(&"beam", 1.0)
	cooldown = settings.cooldown
	var dmg := lerpf(settings.min_damage, settings.max_damage, charge_frac)
	var origin_xz := Vector3(origin.x, 0.0, origin.z)
	var dir := _aim_dir_xz(origin, aim)
	var pulse: Dictionary = {
		"muzzle": muzzle,
		"pos": origin_xz,
		"dir": dir,
		"speed": settings.speed,
		"remaining_range": settings.range,
		"radius": settings.radius,
		"damage": dmg,
		"charge": charge_frac,
		"piercing": charge_frac >= settings.pierce_threshold,
		"hit_ids": [],
	}
	pulses.append(pulse)
	start_point = origin_xz
	visual_origin = pulse.muzzle
	end_point = origin_xz + Vector3(dir.x, 0.0, dir.y) * minf(1.5, settings.range)
	flash_timer = 0.14
	flash_charge = charge_frac
	last_feedback = "Piercing flash launched" if pulse.piercing else "Flash launched (%.0f dmg)" % dmg
	combat_event.emit(&"flash_fire", pulse.muzzle, 0.4 + charge_frac * 0.6)
	if pulse.piercing: combat_event.emit(&"flash_pierce", pulse.muzzle, 1.0)

func step(delta: float, world_delta: float, enemies: Array, muzzle: Vector3) -> void:
	cooldown = maxf(0.0, cooldown - maxf(0.0, delta))
	flash_timer = maxf(0.0, flash_timer - maxf(0.0, delta))

	if charging:
		if not _can_use_tool(&"beam", 1.0):
			charging = false
			charge_time = 0.0
			charge = 0.0
			last_feedback = "Flash empty - press E to repair"
		elif delta > 0.0:
			var was_ready := charge >= settings.pierce_threshold
			charge_time += delta
			charge = clampf(charge_time / maxf(0.05, settings.charge_time), 0.0, 1.0)
			if charge >= settings.pierce_threshold:
				last_feedback = "PIERCE READY - release to fire"
				if not was_ready: combat_event.emit(&"flash_ready", muzzle, 1.0)
			else:
				last_feedback = "Charging Flash %.0f%%" % (charge * 100.0)

	_step_pulses(world_delta, enemies)

func _pulse_hit_ids(raw: Variant) -> Array[int]:
	var result: Array[int] = []
	if raw is Array:
		for id in raw:
			if result.size() >= 32: break
			if int(id) > 0 and not result.has(int(id)): result.append(int(id))
	result.sort()
	return result

func _step_pulses(w_delta: float, enemies: Array) -> void:
	if w_delta <= 0.0 or pulses.is_empty(): return
	var surviving: Array[Dictionary] = []
	for pulse: Dictionary in pulses:
		var start: Vector3 = pulse.pos
		var direction: Vector2 = pulse.dir
		var remaining := float(pulse.remaining_range)
		var distance := minf(remaining, float(pulse.speed) * w_delta)
		if distance <= 0.00001: continue
		var raw_end := start + Vector3(direction.x, 0, direction.y) * distance
		var end := raw_end
		var blocked := false
		if cover != null:
			var clip: Dictionary = cover.clip_segment(start, raw_end)
			blocked = clip.blocked
			end = clip.position
		var a := Vector2(start.x, start.z)
		var b := Vector2(end.x, end.z)
		var hit_ids := _pulse_hit_ids(pulse.get("hit_ids", []))
		var piercing := bool(pulse.get("piercing", float(pulse.get("charge", 0)) >= settings.pierce_threshold))
		var hits: Array[Dictionary] = []
		for enemy in enemies:
			if not _is_live_enemy(enemy): continue
			var node := enemy as Node3D
			var id := _enemy_combat_id(node)
			if hit_ids.has(id): continue
			var center := Vector2(node.global_position.x, node.global_position.z)
			var radius := float(node.radius)
			var t := _swept_circle_entry_t(a, b, center, float(pulse.radius) + radius)
			if node.has_method("flash_entry_t"):
				t = float(node.flash_entry_t(start, end, float(pulse.radius)))
			if t < 0.0: continue
			var toward := a.lerp(b, t) - center
			var normal := toward.normalized() if toward.length_squared() > 0.000001 else -direction
			var contact := center + normal * radius
			var contact3 := Vector3(contact.x, 0, contact.y)
			# A wide pulse touching an edge must never hit through solid cover.
			if cover != null and (cover.clip_segment(start, node.global_position).blocked or cover.clip_segment(start, contact3).blocked): continue
			hits.append({"t": t, "node": node, "id": id, "contact": contact3})
		hits.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			return float(x.t) < float(y.t) if not is_equal_approx(float(x.t), float(y.t)) else int(x.id) < int(y.id))
		start_point = start
		visual_origin = pulse.get("muzzle", start)
		flash_charge = float(pulse.get("charge", 0))
		var consumed := false
		for hit: Dictionary in hits:
			if not _is_live_enemy(hit.node): continue
			# The authoritative swept segment is clipped at the wall, with no
			# target search beyond this straight pulse or bonus chain targeting.
			var direction3 := Vector3(direction.x,0,direction.y)
			var query_distance := minf(remaining, maxf(distance,(hit.node.global_position-start).dot(direction3) + 2.0*float(hit.node.radius)))
			var mechanism_end := start + direction3*query_distance
			if cover != null: mechanism_end = cover.clip_segment(start,mechanism_end).position
			var result := _attack_enemy(hit.node, &"beam", float(pulse.damage), hit.contact,
				{"segment_start": start, "segment_end": end, "radius": float(pulse.radius),
				"charge": float(pulse.get("charge", 0)), "piercing": piercing, "mechanism_end": mechanism_end, "prior_hits": hit_ids.size()})
			hit_ids.append(int(hit.id))
			flash_timer = 0.14
			_record_hit_feedback("Piercing flash" if piercing else "Flash", result)
			if not piercing:
				end = hit.contact
				consumed = true
				break
		end_point = end
		if blocked:
			flash_timer = 0.14
			last_feedback = "Flash stopped by cover"
		if consumed or blocked: continue
		pulse.pos = raw_end
		pulse.remaining_range = maxf(0, remaining - distance)
		pulse.hit_ids = hit_ids
		pulse.piercing = piercing
		if pulse.remaining_range > 0.00001: surviving.append(pulse)
	pulses = surviving


# --- Tool 3: Cone Repeating Pulses & Edge-Volume Sector ---

func cancel_input() -> void:
	charging = false
	charge_time = 0
	charge = 0

func reset_state() -> void:
	cancel_input()
	cooldown = 0
	flash_timer = 0
	start_point = Vector3.ZERO
	end_point = Vector3.ZERO
	visual_origin = Vector3.ZERO
	flash_charge = 0
	pulses.clear()

func capture_state() -> Dictionary:
	return {"cooldown": cooldown, "flash_timer": flash_timer, "start": start_point, "end": end_point,
		"visual_origin": visual_origin, "flash_charge": flash_charge, "pulses": pulses.duplicate(true)}

func restore_state(data: Dictionary) -> void:
	cancel_input()
	cooldown = maxf(0, float(data.get("cooldown", 0)))
	flash_timer = maxf(0, float(data.get("flash_timer", 0)))
	start_point = data.get("start", Vector3.ZERO)
	end_point = data.get("end", Vector3.ZERO)
	visual_origin = data.get("visual_origin", start_point)
	flash_charge = clampf(float(data.get("flash_charge", 0)), 0, 1)
	pulses.clear()
	for raw: Dictionary in data.get("pulses", []):
		if pulses.size() >= settings.max_pulses: break
		pulses.append({"muzzle": Vector3(raw.get("muzzle", raw.get("pos", Vector3.ZERO))),
			"pos": Vector3(raw.get("pos", Vector3.ZERO)), "dir": Vector2(raw.get("dir", Vector2.UP)),
			"speed": maxf(0, float(raw.get("speed", settings.speed))), "remaining_range": maxf(0, float(raw.get("remaining_range", 0))),
			"radius": maxf(0, float(raw.get("radius", settings.radius))), "damage": maxf(0, float(raw.get("damage", settings.min_damage))),
			"charge": clampf(float(raw.get("charge", 0)), 0, 1), "piercing": bool(raw.get("piercing", false)),
			"hit_ids": _pulse_hit_ids(raw.get("hit_ids", []))})
