extends SceneTree
const Trial = preload("res://scenes/navigation/checks/fixture.gd")
var checks := 0
var failures: Array[String] = []
var trial: Node3D
var metrics := {}
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
		printerr("FAIL: " + text)
func values_only(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal or value is RID: return false
	if value is Array:
		for item in value:
			if not values_only(item): return false
	if value is Dictionary:
		for key in value:
			if not values_only(key) or not values_only(value[key]): return false
	return true
func fresh(point: Vector3) -> void:
	trial.director.clear()
	trial.player.position = point
	trial.player.hits = 0
	trial.player.time_controller.begin_attempt()
func run() -> void:
	trial = Trial.new()
	root.add_child(trial)
	trial.director.navigation.sync_region()
	for i in range(180):
		await physics_frame
		if trial.ready_maps(): break
	expect(trial.ready_maps(), "Four native clearance maps become ready from the authored room")
	if not trial.ready_maps():
		finish()
		return
	metrics.bake_usec = trial.director.navigation.build_times_usec.duplicate()
	expect(trial.director.navigation.polygon_counts.size() == 4, "Clearance cache has four bounded native maps")
	expect(not trial.director.navigation.ready_for(10), "Unsupported body size cannot silently use a too-small mesh")
	# Multi-exhibit routes in both directions, with enough world time to contact.
	for reverse in [false, true]:
		fresh(Vector3(0,0,-12) if reverse else Vector3(0,0,12))
		var enemy: CombatEnemy = trial.director.spawn(&"swarmer",Vector3(0,0,12) if reverse else Vector3(0,0,-12))
		var clear := true
		var widest := 0.0
		var max_step := 0.0
		for i in range(300):
			var before := enemy.position
			trial.director.step(.05,trial.player)
			clear = clear and not enemy.overlaps_cover()
			widest = maxf(widest,absf(enemy.position.x))
			max_step = maxf(max_step,enemy.position.distance_to(before))
			await physics_frame
			if trial.player.hits > 0: break
		expect(trial.player.hits > 0 and widest > 2.5, "Native corner/multi-exhibit detour reaches contact; reverse="+str(reverse))
		expect(clear and max_step <= .141, "Detour is cover-safe without a next-point snap")
		metrics["detour_"+str(reverse)] = {"hits":trial.player.hits,"lateral_extent":widest,"max_step":max_step,"queries":enemy.navigation.queries}
	# A full wide silhouette must route outside exhibits, not just its body.
	fresh(Vector3(0,0,12))
	var wide: CombatPatternEnemy = trial.director.spawn(&"loop",Vector3(0,0,-12))
	var wide_clear := true
	var wide_extent := 0.0
	for i in range(450):
		trial.director.step(.1,trial.player)
		wide_clear = wide_clear and not wide.overlaps_cover()
		wide_extent = maxf(wide_extent,absf(wide.position.x))
		await physics_frame
		if wide.position.z > 8: break
	expect(wide_clear and wide_extent > 5.5 and wide.position.z > 8, "Wide loop takes a real full-clearance detour")
	metrics.wide = {"lateral_extent":wide_extent,"final_position":str(wide.position),"clear":wide_clear}
	# Slow time scales locomotion and local separation synchronously. A route in
	# this open lane has no intentional curvature to confound the distance ratio.
	var distances: Array[float] = []
	for scale: float in [1.0,.18]:
		fresh(Vector3(14,0,8))
		var actor: CombatEnemy = trial.director.spawn(&"swarmer",Vector3(14,0,-12))
		var traveled := 0.0
		for i in range(50):
			var before := actor.position
			trial.director.step(.02*scale,trial.player)
			traveled += actor.position.distance_to(before)
			await physics_frame
		distances.append(traveled)
	expect(absf(distances[1]/distances[0]-.18)<.005, "Slow movement uses exact world delta, including route/local steering")
	metrics.slow_ratio = distances[1]/distances[0]
	fresh(Vector3(0,0,12))
	var replay: CombatEnemy = trial.director.spawn(&"blue",Vector3(0,0,-12))
	for i in range(90):
		trial.director.step(.05,trial.player)
		await physics_frame
	var snapshot: Dictionary = trial.director.capture_state()
	var saved: Vector3 = replay.position
	expect(values_only(snapshot), "Snapshots contain values/intent only, no RIDs, agents, paths or future velocity")
	for i in range(30):
		trial.director.step(.05,trial.player)
		await physics_frame
	trial.director.restore_state(snapshot)
	expect(replay.position == saved, "Restoring a detour restores the exact actor pose")
	var advances := replay.navigation.advances
	var queries := replay.navigation.queries
	var path_index := replay.navigation.get_current_navigation_path_index()
	for i in range(8):
		trial.director.step(0,trial.player)
		await physics_frame
	expect(replay.navigation.advances == advances and replay.navigation.queries == queries and replay.navigation.get_current_navigation_path_index() == path_index and replay.position == saved, "Frozen scrub never advances the agent or actor")
	trial.director.step(.05,trial.player)
	expect(replay.position.distance_to(saved) <= .113 and not replay.overlaps_cover(), "Rebuilt route takes a bounded next step, without a rewind snap")
	await physics_frame
	replay.apply_control(Vector3.LEFT,12,.7)
	var moved := replay.position
	trial.director.step(.05,trial.player)
	expect(replay.position.distance_to(moved)>.1 and replay.is_staggered() and not replay.overlaps_cover(), "Knockback/stagger still displace through the single collision owner")
	await physics_frame
	var frozen: Dictionary = trial.director.capture_state()
	advances = replay.navigation.advances
	trial.player.time_controller.force_depletion()
	for i in range(5):
		trial.director.step(.5,trial.player)
		await physics_frame
	expect(replay.navigation.advances == advances and trial.director.capture_state().enemies == frozen.enemies, "Emergency blocks even an incorrectly positive caller delta")
	# A missing/disabled region causes a hold, never a second routing algorithm.
	fresh(Vector3(14,0,8))
	var waiting: CombatEnemy = trial.director.spawn(&"blue",Vector3(14,0,-12))
	trial.region.enabled = false
	trial.director.step(.05,trial.player)
	var held := waiting.position
	for i in range(4):
		trial.director.step(.05,trial.player)
		await physics_frame
	expect(waiting.position == held, "No active authored region means no substitute routing or invisible room")
	trial.region.enabled = true
	for i in range(120):
		trial.director.step(.05,trial.player)
		await physics_frame
		if waiting.position.distance_to(held)>.2: break
	expect(waiting.position.distance_to(held)>.2, "Re-enabled region rebuilds the native route and resumes bounded movement")
	var original: NavigationMesh = trial.region.navigation_mesh
	var empty := NavigationMesh.new()
	empty.agent_radius = 0
	trial.region.navigation_mesh = empty
	for i in range(5):
		trial.director.step(.05,trial.player)
		await physics_frame
	held = waiting.position
	expect(not trial.director.navigation.ready_for(.65), "An initially empty room mesh holds routing")
	empty.set_vertices(original.get_vertices())
	for i in range(original.get_polygon_count()): empty.add_polygon(original.get_polygon(i))
	# NavigationMesh source edits emit changed through the native region.
	empty.emit_changed()
	for i in range(120):
		trial.director.step(.05,trial.player)
		await physics_frame
		if waiting.position.distance_to(held)>.2: break
	expect(waiting.position.distance_to(held)>.2, "An in-place completed room bake is discovered without a fallback scene")
	finish()
func finish() -> void:
	trial.queue_free()
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"metrics":metrics}))
	quit(0 if failures.is_empty() else 1)
