extends SceneTree

const DirectorScript := preload("res://scenes/prototype/enemies.gd")
const FlowScript := preload("res://scenes/prototype/flow.gd")
const CoverScript := preload("res://scenes/prototype/cover.gd")
const NavFixture := preload("res://scenes/navigation/checks/fixture.gd")

var checks := 0
var failures: Array[String] = []
var metrics := {}


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


static func _stats_usec(samples: Array[int]) -> Dictionary:
	if samples.is_empty():
		return {"count": 0, "total_usec": 0, "median_usec": 0, "p95_usec": 0, "worst_usec": 0}
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var total := 0
	for s in sorted:
		total += s
	var n := sorted.size()
	var median: int = sorted[n / 2]
	var p95: int = sorted[mini(n - 1, int(floor(float(n) * 0.95)))]
	var worst: int = sorted[n - 1]
	return {
		"count": n,
		"total_usec": total,
		"median_usec": median,
		"p95_usec": p95,
		"worst_usec": worst,
	}


func run() -> void:
	var trial := NavFixture.new()
	root.add_child(trial)
	trial.director.navigation.sync_region()
	for i in range(180):
		await physics_frame
		if trial.ready_maps():
			break
	expect(trial.ready_maps(), "Navigation fixture maps ready for director/flow benchmark")

	var director: Node3D = trial.director
	var player: Node3D = trial.player
	player.position = Vector3(0.0, 0.0, 12.0)
	player.time_controller.begin_attempt()

	# 1. Seeded formation placement (flow.layout) equivalence & timing
	director.clear()
	director.cover.set_rectangles(NavFixture.BLOCKS)
	director.spawn_formation(&"curve", [&"blue", &"blue", &"yellow", &"orange"], player, 101)
	director.spawn_formation(&"line", [&"side_guard", &"front_guard", &"ranged"], player, 202)
	director.spawn_formation(&"cluster", [&"loop", &"blue", &"yellow"], player, 303)
	expect(director.enemies.size() == 7, "Seeded occupied crowd spawned for layout benchmark (%d)" % director.enemies.size())

	var layout_rosters: Array[Array] = [
		[&"blue", &"blue", &"yellow", &"orange", &"side_guard"],
		[&"loop", &"pair", &"blue", &"yellow"],
		[&"loop_boss", &"blue", &"yellow", &"orange"],
		[&"front_guard", &"side_guard", &"orange", &"blue", &"yellow", &"swarmer"],
	]
	var formations: Array[StringName] = [&"curve", &"line", &"cluster", &"mixed"]
	var layout_samples: Array[int] = []
	var layout_checksum := 0.0
	var layout_slot_total := 0

	var probe_flow := FlowScript.new()
	for iter in range(40):
		probe_flow.arrival_index = iter % 4
		var form: StringName = formations[iter % formations.size()]
		var roster: Array = layout_rosters[iter % layout_rosters.size()]
		var t0 := Time.get_ticks_usec()
		var slots: Array[Dictionary] = probe_flow.layout(form, roster, player.position, director.cover, 1000 + iter * 17, director.enemies)
		var elapsed := Time.get_ticks_usec() - t0
		layout_samples.append(elapsed)
		layout_slot_total += slots.size()
		for s_idx in range(slots.size()):
			var slot: Dictionary = slots[s_idx]
			var p: Vector3 = slot["position"]
			layout_checksum += p.x * float(s_idx + 1) * 1.31 + p.z * float(iter + 1) * 0.73 + float(slot["radius"]) * 2.17 + float(slot["source_index"]) * 5.0

	metrics["layout_40_calls"] = _stats_usec(layout_samples)
	metrics["layout_slot_total"] = layout_slot_total
	metrics["layout_checksum"] = snappedf(layout_checksum, 0.0001)
	expect(layout_slot_total == 110 and is_equal_approx(snappedf(layout_checksum, 0.0001), 12921.7459),
		"All 40 seeded layout calls match exact BASE slot count (%d) and checksum (%.4f)" % [layout_slot_total, snappedf(layout_checksum, 0.0001)])

	# 2. Cohort advance + cohesion + approach_scale micro-benchmark & invariants
	director.clear()
	director.cover.set_rectangles(NavFixture.BLOCKS)
	player.position = Vector3(0.0, 0.0, 12.0)
	player.time_controller.begin_attempt()
	director.spawn_formation(&"curve", [&"blue", &"blue", &"blue", &"yellow", &"orange", &"ranged"], player, 11)
	director.spawn_formation(&"line", [&"side_guard", &"front_guard", &"blue", &"yellow", &"orange", &"ranged"], player, 22)
	director.spawn_formation(&"cluster", [&"blue", &"yellow", &"orange", &"swarmer", &"skirmisher", &"ranged"], player, 33)
	director.spawn_formation(&"mixed", [&"loop", &"pair", &"blue", &"yellow", &"orange", &"ranged"], player, 44)
	expect(director.enemies.size() == 24 and director.flow.cohorts.size() == 4,
		"Spawned 24 enemies across 4 cohorts for director/flow step benchmark (enemies=%d, cohorts=%d)" % [director.enemies.size(), director.flow.cohorts.size()])

	# Launch 12 projectiles (6 owned by live ranged units, 6 unowned probes)
	var ranged_ids: Array[int] = []
	for e in director.enemies:
		if e.kind == &"ranged":
			ranged_ids.append(int(e.combat_id()))
	for i in range(6):
		var owner_id: int = ranged_ids[i % ranged_ids.size()]
		var owner_node: Node3D = null
		for e in director.enemies:
			if int(e.combat_id()) == owner_id:
				owner_node = e
				break
		var origin := owner_node.position + Vector3(0.0, 0.0, 0.9)
		expect(director.launch_projectile(origin, Vector3(0.2 * float(i - 2), 0.0, 1.0), 8.0, 6.5, owner_id),
			"Launched owner-bound projectile %d" % i)
	for i in range(6):
		expect(director.launch_projectile(Vector3(-8.0 + float(i) * 3.0, 0.0, -14.0), Vector3(0.0, 0.0, 1.0), 6.0, 5.5, 0),
			"Launched standalone projectile %d" % i)
	expect(director.projectiles.size() == 12, "12 active projectiles in flight")

	var base_flow_state: Dictionary = director.flow.capture_state()
	var snapshot_24: Array[Node3D] = director.enemies.duplicate()
	var flow_micro_samples: Array[int] = []
	for iter in range(200):
		director.flow.restore_state(base_flow_state)
		var t0 := Time.get_ticks_usec()
		# Step once through warning and once into opportunity window
		var h1: Dictionary = director.flow.advance(0.5, snapshot_24, player)
		var c1: Dictionary = director.flow.cohesion(0.5, snapshot_24, h1)
		var h2: Dictionary = director.flow.advance(0.6, snapshot_24, player)
		var c2: Dictionary = director.flow.cohesion(0.6, snapshot_24, h2)
		var scale_sum := 0.0
		for e in snapshot_24:
			scale_sum += director.flow.approach_scale(int(e.combat_id()))
		var elapsed := Time.get_ticks_usec() - t0
		flow_micro_samples.append(elapsed)
		if iter == 0:
			expect(h1.size() == 24 and c1.is_empty(), "Warning phase holds all 24 cohort members and applies no cohesion bias")
			expect(h2.size() == 24 and c2.size() > 0 and scale_sum < 24.0, "Opportunity window applies cohesion bias and approach scale")
	director.flow.restore_state(base_flow_state)
	metrics["flow_micro_200_iters"] = _stats_usec(flow_micro_samples)

	# 3. Director bookkeeping + visual sync micro-benchmark (prune + orphan check + arrival draw + projectile visuals)
	var director_maint_samples: Array[int] = []
	for iter in range(200):
		var t0 := Time.get_ticks_usec()
		director._prune_dead_enemies()
		director._discard_orphaned_projectiles()
		director._draw_arrivals()
		director._sync_projectile_visuals()
		var elapsed := Time.get_ticks_usec() - t0
		director_maint_samples.append(elapsed)
	metrics["director_maint_200_iters"] = _stats_usec(director_maint_samples)

	# 4. Real 180-tick simulation of director.step() with state capture/restore and emergency freeze verification
	var step_samples: Array[int] = []
	var mid_snapshot: Dictionary = {}
	for tick in range(180):
		var t0 := Time.get_ticks_usec()
		director.step(1.0 / 60.0, player)
		var elapsed := Time.get_ticks_usec() - t0
		step_samples.append(elapsed)
		if tick == 45:
			mid_snapshot = director.capture_state()
		elif tick == 90:
			# Kill one ranged owner and verify its projectile is pruned on the next step
			for e in director.enemies:
				if e.kind == &"ranged" and e.health > 0.0:
					e.health = 0.0
					break
	metrics["director_step_180_ticks"] = _stats_usec(step_samples)
	expect(director.enemies.size() == 23, "Dead ranged enemy was pruned cleanly during step loop (%d remaining)" % director.enemies.size())

	# Verify exact capture_state / restore_state round-trip
	director.restore_state(mid_snapshot)
	var restored_check: Dictionary = director.capture_state()
	expect(restored_check == mid_snapshot, "director.restore_state reproduces exact mid-simulation capture_state")

	# Verify synchronous emergency callback protection during roster step
	director.clear()
	player.time_controller.begin_attempt()
	player.time_controller.try_spend(player.time_controller.capacity - 2.0)
	var emerg_state := {"triggered": false}
	var on_emerg := func(_charges: int) -> void:
		emerg_state["triggered"] = true
		director.restore_state(mid_snapshot)
	player.time_controller.emergency_started.connect(on_emerg, CONNECT_ONE_SHOT)
	var _attacker: Node3D = director.spawn(&"swarmer", player.position)
	var _trailing_a: Node3D = director.spawn(&"blue", Vector3(-6.0, 0.0, 12.0))
	var _trailing_b: Node3D = director.spawn(&"yellow", Vector3(6.0, 0.0, 12.0))
	director.step(0.05, player)
	expect(bool(emerg_state["triggered"]) and director.enemies.size() == mid_snapshot["enemies"].size(),
		"Synchronous emergency restore inside step() aborts stale roster iteration cleanly")

	trial.queue_free()
	await process_frame
	print(JSON.stringify({
		"status": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
		"metrics": metrics,
	}))
	quit(0 if failures.is_empty() else 1)
