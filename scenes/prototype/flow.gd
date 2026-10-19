class_name CombatFlow
extends RefCounted

# Small, value-only world-time formation state. The director remains the owner
# of enemy nodes, AI, attacks and roster bounds. No campaign or independent clock.
const Tuning = preload("res://scenes/prototype/tuning.gd")
const WARNING_SECONDS := 0.9
const OPPORTUNITY_SECONDS := 2.4
const RECOVERY_SECONDS := 4.7
const MAX_COHORTS := 8
const MAX_MEMBERS := 8
var arrival_index := 0
var cohorts: Array[Dictionary] = []
var pressure_active := false
var pressure_elapsed := 0.0
var pressure_index := 0
var pressure_seed := 0


func reset() -> void:
	arrival_index = 0
	cohorts.clear()
	pressure_active = false
	pressure_elapsed = 0
	pressure_index = 0
	pressure_seed = 0


# Clearance includes visible appendages plus room for a real cutter sweep. The
# collision radius remains controller-owned; this is an arrival reservation.
const PatternVisual = preload("res://scenes/prototype/pattern_visual.gd")
const UNIT_CLEARANCE = {&"blue": 1.5, &"yellow": 0.85, &"orange": 1.1,
	&"side_guard": 2.15, &"front_guard": 1.25, &"warden": 1.8, &"pair": 1.8}

static func _is_pattern_kind(kind: StringName) -> bool:
	return kind == &"loop" or kind == &"zigzag" or kind == &"pair" or kind == &"loop_boss" or kind == &"sequence_boss" or kind == &"final_boss"

static func placement_radius(kind: StringName) -> float:
	var body := float(Tuning.ENEMIES.get(String(kind), {}).get("radius", 0.8))
	var radius := maxf(body, PatternVisual.silhouette_radius(kind) + float(Tuning.RING.radius) + 0.2) if _is_pattern_kind(kind) else maxf(body, float(UNIT_CLEARANCE.get(kind, body)))
	return radius

# Prefer complete silhouettes inside the normal gameplay perspective. This is
# only a candidate preference: a crowded room can still use a safe off-axis
# fallback. No Camera/Node reference is stored in formation or rewind state.
static func readable_from_player(point: Vector3, extent: float, player: Vector3) -> bool:
	var view := Basis.from_euler(Vector3(deg_to_rad(-55), 0, 0)).inverse()
	var relative_position := point - (player + Vector3(0, 20, 14))
	var half_y := tan(deg_to_rad(float(Tuning.VIEW.fov)) * .5)
	var limit_y := half_y * .92
	var limit_x := half_y * 1.6 * .94
	# Visit the eight box corners without allocating nested temporary arrays.
	for corner in range(8):
		var corner_x := -extent if (corner & 4) == 0 else extent
		var corner_z := -extent if (corner & 2) == 0 else extent
		var corner_y := 0.0 if (corner & 1) == 0 else 5.2
		var local := view * (relative_position + Vector3(corner_x, corner_y, corner_z))
		if local.z >= 0 or absf(local.y) > -local.z * limit_y or absf(local.x) > -local.z * limit_x:
			return false
	return true

func _free_slot(point: Vector3, extent: float, player_position: Vector3, cover: RefCounted, occupied_positions: PackedVector3Array, occupied_clearances: PackedFloat64Array, slots: Array[Dictionary], is_pattern: bool) -> bool:
	var limit := float(Tuning.ARENA_HALF_SIZE) - extent - 0.6
	if absf(point.x) > limit or absf(point.z) > limit or point.distance_to(player_position) < maxf(5.0, extent + 1.4): return false
	for occupied_index in range(occupied_positions.size()):
		if point.distance_to(occupied_positions[occupied_index]) < extent + occupied_clearances[occupied_index]: return false
	for prior: Dictionary in slots:
		if point.distance_to(prior.position) < extent + float(prior.radius) + 0.15: return false
	if cover != null:
		if cover.clip_segment(point, point, extent + 0.15).blocked: return false
		if is_pattern and cover.clip_segment(player_position, point, float(Tuning.RING.radius)).blocked: return false
	return true

func layout(formation: StringName, kinds: Array, player_position: Vector3, cover: RefCounted, seed: int, occupied: Array) -> Array[Dictionary]:
	var count := mini(kinds.size(), MAX_MEMBERS)
	var best: Array[Dictionary] = []
	if count == 0 or cohorts.size() >= MAX_COHORTS: return best
	var player := Vector3(player_position.x, 0, player_position.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var jitter: Array[float] = []
	var extents: Array[float] = []
	var member_kinds: Array[StringName] = []
	var member_is_pattern: Array[bool] = []
	var widest := 0.0
	for i in range(count):
		var k := StringName(kinds[i])
		member_kinds.append(k)
		member_is_pattern.append(_is_pattern_kind(k))
		jitter.append(rng.randf_range(-0.22, 0.22))
		extents.append(placement_radius(k))
		widest = maxf(widest, extents[-1])
	var occupied_positions := PackedVector3Array()
	var occupied_clearances := PackedFloat64Array()
	for node in occupied:
		if is_instance_valid(node) and node.health > 0:
			occupied_positions.append(Vector3(node.position.x, 0, node.position.z))
			occupied_clearances.append(placement_radius(StringName(node.kind)) + 0.25)
	# First use the authored formation at one entrance, scaled for its members.
	# Alternative distances and entrances preserve a usable escape side.
	var entrance := posmod(arrival_index + seed, 4)
	var spacing := maxf(1.65, widest * 2 + 0.2)
	for attempt in range(32):
		for distance: float in [9.0, 11.5, 7.0, 13.5]:
			var angle := -PI * 0.5 + float(entrance) * PI * 0.5 + float(attempt) * TAU / 32
			var radial := Vector3(cos(angle), 0, sin(angle))
			var side := Vector3(-radial.z, 0, radial.x)
			var slots: Array[Dictionary] = []
			for i in range(count):
				var index := float(i) - float(count - 1) * 0.5
				var point := player + radial * distance
				match formation:
					&"line":
						var along := distance - 2.2
						for j in range(i): along += extents[j] + extents[j + 1] + 0.45
						point = player + radial * (along + jitter[i] * .30) + side * jitter[i] * .50
					&"cluster":
						point += side * (float(i % 3) - float(mini(count, 3) - 1) * 0.5) * spacing
						point += radial * float(i / 3) * spacing + side * jitter[i] * 0.2
					_:
						var arc := index * maxf(0.21, spacing / distance)
						point = player + (radial * cos(arc) + side * sin(arc)) * (distance + jitter[i])
				if not _free_slot(point, extents[i], player, cover, occupied_positions, occupied_clearances, slots, member_is_pattern[i]): break
				if extents[i] > 3.0 and not readable_from_player(point, extents[i], player): break
				if formation == &"line" and cover != null and cover.clip_segment(player, point).blocked: break
				slots.append({"kind": member_kinds[i], "position": point, "radius": extents[i], "source_index": i})
			if slots.size() > best.size(): best = slots
			if best.size() == count: return best
	# A wall/occupied entrance can defeat the whole shape. Search independently
	# for the missing members, rather than retrying that same shape forever.
	# Finite room grid, no timer/node state; deterministic and rewind-independent.
	var entrance_angle := -PI * 0.5 + float(entrance) * PI * 0.5
	var desired := player + Vector3(cos(entrance_angle), 0, sin(entrance_angle)) * 9.0
	for i in range(count):
		var included := false
		for slot: Dictionary in best:
			if int(slot.source_index) == i: included = true
		if included: continue
		var candidate := Vector3.ZERO
		var score := INF
		var member_extent := extents[i]
		var member_is_cuttable := member_is_pattern[i]
		for x in range(-16, 17, 2):
			for z in range(-16, 17, 2):
				var point := Vector3(x, 0, z)
				var relative := point - player
				var cost := point.distance_squared_to(desired) + absf(relative.length() - 9) * 3
				if cost >= score: continue
				if not _free_slot(point, member_extent, player, cover, occupied_positions, occupied_clearances, best, member_is_cuttable): continue
				if member_extent > 3.0 and not readable_from_player(point, member_extent, player): cost += 10000
				if cost < score:
					score = cost
					candidate = point
		if score < INF: best.append({"kind": member_kinds[i], "position": candidate, "radius": member_extent, "source_index": i})
		else: break # Keep the director's finite roster prefix intact.
	best.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.source_index) < int(b.source_index))
	return best


static func safe(point: Vector3, radius: float, player_position: Vector3, cover: RefCounted) -> bool:
	var limit := float(Tuning.ARENA_HALF_SIZE) - radius - 0.6
	if absf(point.x) > limit or absf(point.z) > limit or point.distance_to(Vector3(player_position.x, 0, player_position.z)) < maxf(5.0, radius + 1.4): return false
	return cover == null or not cover.clip_segment(point, point, radius + 0.15).blocked


func add(formation: StringName, members: Array[Node3D]) -> void:
	if members.is_empty(): return
	var center := Vector3.ZERO
	for node in members: center += node.position
	center /= members.size()
	var ids: Array[int] = []
	var offsets: Array[Vector3] = []
	for node in members:
		ids.append(int(node.combat_id()))
		offsets.append(node.position - center)
	cohorts.append({"formation": formation, "ids": ids, "offsets": offsets, "center": center,
		"warning": WARNING_SECONDS, "window": OPPORTUNITY_SECONDS})
	arrival_index += 1


func advance(world_delta: float, nodes: Array[Node3D], player: Node3D) -> Dictionary:
	var dt := maxf(0, world_delta)
	if dt <= 0 or cohorts.is_empty(): return {}
	var by_id := {}
	for node in nodes:
		if is_instance_valid(node) and node.health > 0: by_id[int(node.combat_id())] = node
	var holds := {}
	var live: Array[Dictionary] = []
	var has_player := is_instance_valid(player)
	var player_pos := player.position if has_player else Vector3.ZERO
	for cohort: Dictionary in cohorts:
		var valid := false
		var contact := false
		for id in cohort.ids:
			if not by_id.has(id): continue
			valid = true
			var node: Node3D = by_id[id]
			if has_player and node.position.distance_to(player_pos) < 3.25: contact = true
			if node.attack_phase != &"approach" or node.stagger_timer > 0 or node.knockback_vel.length_squared() > 0.01: contact = true
		if not valid: continue
		if contact: continue
		var waiting := minf(dt, float(cohort.warning))
		for id in cohort.ids: holds[id] = waiting
		cohort.warning = maxf(0, float(cohort.warning) - dt)
		cohort.window = maxf(0, float(cohort.window) - (dt - waiting))
		# Contact/control has already released the entire cohort, including
		# its warning hold; native windup/recovery is never held back.
		if cohort.warning > 0 or cohort.window > 0: live.append(cohort)
	cohorts = live
	return holds


func cohesion(dt: float, nodes: Array[Node3D], holds: Dictionary = {}) -> Dictionary:
	var biases := {}
	if dt <= 0 or cohorts.is_empty(): return biases
	var has_active_window := false
	for cohort: Dictionary in cohorts:
		if float(cohort.warning) <= 0.0 and float(cohort.window) > 0.0:
			has_active_window = true
			break
	if not has_active_window: return biases
	var by_id := {}
	for node in nodes:
		if is_instance_valid(node) and node.health > 0: by_id[int(node.combat_id())] = node
	for cohort: Dictionary in cohorts:
		if cohort.warning > 0 or cohort.window <= 0: continue
		var center := Vector3.ZERO
		var count := 0
		for id in cohort.ids:
			if by_id.has(id):
				center += by_id[id].position
				count += 1
		if count < 2: continue
		center /= count
		var maximum_bias := .35 * clampf(float(cohort.window) / OPPORTUNITY_SECONDS, 0, 1)
		for i in range(cohort.ids.size()):
			var member_id: int = cohort.ids[i]
			if not by_id.has(member_id): continue
			var node: Node3D = by_id[member_id]
			if node.attack_phase != &"approach" or node.stagger_timer > 0 or node.knockback_vel.length_squared() > 0.01: continue
			# Soft lateral steering only; native chase, knockback, windup and
			# recovery remain authoritative. No snapping or rigid formation.
			var toward: Vector3 = center + cohort.offsets[i] - node.position
			var forward: Vector3 = node.facing
			toward -= forward * toward.dot(forward)
			if dt - float(holds.get(member_id, 0.0)) <= 0: continue
			biases[member_id] = toward.limit_length(maximum_bias)
	return biases


func approach_scale(id: int) -> float:
	# A brief easing out of the arrival hold gives a hand-drawn sweep time to
	# travel. Speed returns smoothly to normal; contact/control releases it.
	# The existing finite cohort window is the only state and cannot renew.
	for cohort: Dictionary in cohorts:
		if cohort.warning <= 0 and id in cohort.ids:
			return lerpf(1.0, .72, clampf(float(cohort.window) / OPPORTUNITY_SECONDS, 0, 1))
	return 1.0


func start_pressure(seed: int) -> void:
	pressure_active = true
	pressure_elapsed = 0
	pressure_index = 0
	pressure_seed = seed


func next_burst(world_delta: float, player: Node3D) -> Dictionary:
	if not pressure_active or not is_instance_valid(player): return {}
	if not player.can_act:
		# Emergency pauses the schedule; exhaustion ends this room attempt.
		if player.time_controller.exhausted: pressure_active = false
		return {}
	pressure_elapsed += maxf(0, world_delta)
	var interval := WARNING_SECONDS + OPPORTUNITY_SECONDS + RECOVERY_SECONDS
	if pressure_elapsed < float(pressure_index) * interval: return {}
	# A large step may cross more than one deadline. Drop overdue pacing time
	# rather than dumping several arrivals on consecutive recovery-free ticks.
	pressure_elapsed = minf(pressure_elapsed, float(pressure_index) * interval)
	var formation: StringName = [&"curve", &"line", &"cluster"][pressure_index]
	var kind: StringName = [&"blue", &"yellow", &"orange"][pressure_index]
	pressure_index += 1
	if pressure_index >= 3: pressure_active = false
	return {"formation": formation, "kinds": [kind, kind, kind], "seed": pressure_seed}


func capture_state() -> Dictionary:
	return {"arrival_index": arrival_index, "cohorts": cohorts.duplicate(true),
		"pressure_active": pressure_active, "pressure_elapsed": pressure_elapsed,
		"pressure_index": pressure_index, "pressure_seed": pressure_seed}


func restore_state(data: Dictionary) -> void:
	reset()
	arrival_index = maxi(0, int(data.get("arrival_index", 0)))
	pressure_index = clampi(int(data.get("pressure_index", 0)), 0, 3)
	pressure_active = bool(data.get("pressure_active", false)) and pressure_index < 3
	pressure_elapsed = maxf(0, float(data.get("pressure_elapsed", 0)))
	pressure_seed = int(data.get("pressure_seed", 0))
	for raw: Dictionary in data.get("cohorts", []):
		if cohorts.size() >= MAX_COHORTS: break
		var ids: Array[int] = []
		var offsets: Array[Vector3] = []
		for i in range(mini(MAX_MEMBERS, mini(raw.get("ids", []).size(), raw.get("offsets", []).size()))):
			ids.append(int(raw.ids[i]))
			offsets.append(Vector3(raw.offsets[i]))
		if ids.is_empty(): continue
		cohorts.append({"formation": StringName(raw.get("formation", "mixed")), "ids": ids, "offsets": offsets,
			"center": Vector3(raw.get("center", Vector3.ZERO)), "warning": clampf(float(raw.get("warning", 0)), 0, WARNING_SECONDS),
			"window": clampf(float(raw.get("window", 0)), 0, OPPORTUNITY_SECONDS)})
