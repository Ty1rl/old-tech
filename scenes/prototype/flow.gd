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


func layout(formation: StringName, kinds: Array, player_position: Vector3, cover: RefCounted, seed: int, occupied: Array) -> Array[Dictionary]:
	var count := mini(kinds.size(), MAX_MEMBERS)
	var best: Array[Dictionary] = []
	if count == 0 or cohorts.size() >= MAX_COHORTS: return best
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var jitter: Array[float] = []
	for i in range(count): jitter.append(rng.randf_range(-0.10, 0.10))
	# One narrow entrance per group leaves the opposite half of the room open.
	var entrance := posmod(arrival_index + seed, 4)
	for attempt in range(32):
		var angle := -PI * 0.5 + float(entrance) * PI * 0.5 + float(attempt) * TAU / 32
		var radial := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-radial.z, 0, radial.x)
		var slots: Array[Dictionary] = []
		for i in range(count):
			var index := float(i) - float(count - 1) * 0.5
			var point := player_position + radial * 9.0
			match formation:
				&"line":
					# Radial file: one aimed charged shot can intersect the line.
					point = player_position + radial * (6.8 + float(i) * 1.85) + side * jitter[i] * 0.30
				&"cluster":
					point += side * (float(i % 3) - float(mini(count, 3) - 1) * 0.5) * 1.65
					point += radial * float(i / 3) * 1.65 + side * jitter[i]
				_:
					var arc := index * 0.21
					point = player_position + (radial * cos(arc) + side * sin(arc)) * (9.0 + jitter[i])
			point.y = 0
			var kind := StringName(kinds[i])
			var radius := float(Tuning.ENEMIES.get(String(kind), {}).get("radius", 0.8))
			if not safe(point, radius, player_position, cover): continue
			var crowded := false
			for node in occupied:
				if is_instance_valid(node) and node.health > 0 and point.distance_to(node.position) < radius + float(node.radius) + 0.25:
					crowded = true
			for prior: Dictionary in slots:
				if point.distance_to(prior.position) < radius + float(prior.radius) + 0.15: crowded = true
			if not crowded: slots.append({"kind": kind, "position": point, "radius": radius})
		if slots.size() > best.size(): best = slots
		if best.size() == count: break
	return best


static func safe(point: Vector3, radius: float, player_position: Vector3, cover: RefCounted) -> bool:
	var limit := float(Tuning.ARENA_HALF_SIZE) - radius - 0.6
	if absf(point.x) > limit or absf(point.z) > limit or point.distance_to(Vector3(player_position.x, 0, player_position.z)) < 5.0: return false
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
	if dt <= 0: return {}
	var by_id := {}
	for node in nodes:
		if is_instance_valid(node) and node.health > 0: by_id[int(node.combat_id())] = node
	var holds := {}
	var live: Array[Dictionary] = []
	for cohort: Dictionary in cohorts:
		var valid := false
		var contact := false
		for id in cohort.ids:
			if not by_id.has(id): continue
			valid = true
			var node: Node3D = by_id[id]
			if is_instance_valid(player) and node.position.distance_to(player.position) < 3.25: contact = true
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


func cohere(dt: float, nodes: Array[Node3D], cover: RefCounted, holds: Dictionary = {}) -> void:
	if dt <= 0: return
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
		for i in range(cohort.ids.size()):
			if not by_id.has(cohort.ids[i]): continue
			var node: Node3D = by_id[cohort.ids[i]]
			if node.attack_phase != &"approach" or node.stagger_timer > 0 or node.knockback_vel.length_squared() > 0.01: continue
			# Soft lateral steering only; native chase, knockback, windup and
			# recovery remain authoritative. No snapping or rigid formation.
			var toward: Vector3 = center + cohort.offsets[i] - node.position
			var forward: Vector3 = node.facing
			toward -= forward * toward.dot(forward)
			var active_dt := maxf(0, dt - float(holds.get(int(node.combat_id()), 0.0)))
			var correction := toward.limit_length(0.35 * minf(active_dt, float(cohort.window)))
			if cover == null or not cover.clip_segment(node.position, node.position + correction, float(node.radius)).blocked:
				node.position += correction


func start_pressure(seed: int) -> void:
	pressure_active = true
	pressure_elapsed = 0
	pressure_index = 0
	pressure_seed = seed


func next_burst(world_delta: float, player: Node3D) -> Dictionary:
	if not pressure_active or not is_instance_valid(player): return {}
	if float(player.health) <= 0:
		pressure_active = false
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
