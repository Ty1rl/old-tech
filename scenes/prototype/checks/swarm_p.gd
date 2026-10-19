extends SceneTree
const Trial = preload("res://scenes/navigation/checks/fixture.gd")
var trial: Node3D
var checks := 0
var failures: Array[String] = []
var metrics := {}
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
		printerr("FAIL: "+text)
func button(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event
func fresh() -> void:
	trial.director.clear()
	trial.player.position = Vector3(12,0,12)
	trial.player.hits = 0
	trial.player.time_controller.begin_attempt()
	trial.equipment.reset_state()
	trial.weapons.reset_state()
func tick(dt: float, aim: Vector3) -> void:
	trial.weapons.step(dt,trial.player,aim,trial.director.enemies,dt)
	trial.director.step(dt,trial.player)
	await physics_frame
func run() -> void:
	trial = Trial.new()
	root.add_child(trial)
	trial.director.navigation.sync_region()
	for i in range(180):
		await physics_frame
		if trial.ready_maps(): break
	expect(trial.ready_maps(),"Native maps ready for the 32-agent/weapon trial")
	if not trial.ready_maps():
		finish()
		return
	fresh()
	trial.player.position = Vector3(0,0,12)
	var starts: Array[Vector3] = []
	for z in range(4):
		for x in range(8):
			var kind: StringName = [&"blue",&"yellow",&"orange"][(x+z)%3]
			var actor: CombatEnemy = trial.director.spawn(kind,Vector3(x*3-11,0,-16+z*2))
			starts.append(actor.position)
	expect(trial.director.enemies.size()==32,"All 32 actual agents use one bounded director")
	var times: Array[int] = []
	var nav_times: Array[int] = []
	var reversals := 0
	var previous: Array[Vector3] = []
	previous.resize(32)
	previous.fill(Vector3.ZERO)
	var safe := true
	var max_step := 0.0
	var pressure_frames := 0
	var peak_close := 0
	for frame in range(600):
		var before: Array[Vector3] = []
		for actor in trial.director.enemies: before.append(actor.position)
		var start := Time.get_ticks_usec()
		trial.director.step(.05,trial.player)
		times.append(Time.get_ticks_usec()-start)
		var close_this_frame := 0
		for i in range(32):
			var actor: CombatEnemy = trial.director.enemies[i]
			var step := actor.position-before[i]
			max_step=maxf(max_step,step.length())
			if step.length()>.005 and previous[i].length()>.005 and step.dot(previous[i])<0: reversals+=1
			previous[i]=step
			safe=safe and not actor.overlaps_cover()
			if actor.position.distance_to(trial.player.position)<5: close_this_frame+=1
		peak_close=maxi(peak_close,close_this_frame)
		if close_this_frame>=3: pressure_frames+=1
		await physics_frame
		nav_times.append(int(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS)*1000000))
	var nearest := 100.0
	var progressed := 0
	var blocked: Array[Dictionary] = []
	var close := 0
	var queries := 0
	var angles: Array[float] = []
	for i in range(32):
		var actor: CombatEnemy = trial.director.enemies[i]
		queries+=actor.navigation.queries
		if actor.position.distance_to(starts[i])>6: progressed+=1
		else:
			var path:=actor.navigation.get_current_navigation_path()
			var index:=actor.navigation.get_current_navigation_path_index()
			blocked.append({"kind":actor.kind,"position":str(actor.position),"start":str(starts[i]),"goal":str(actor.navigation.target_position),"height":actor.navigation.path_height_offset,"next":str(path[index]) if not path.is_empty() else "empty","index":index})
		if actor.position.distance_to(trial.player.position)<5: close+=1
		var direction: Vector3=actor.position-trial.player.position
		angles.append(fposmod(atan2(direction.z,direction.x),TAU))
		for j in range(i+1,32):
			var other: CombatEnemy=trial.director.enemies[j]
			nearest=minf(nearest,actor.position.distance_to(other.position)/(actor.radius+other.radius))
	angles.sort()
	var escape_gap := 0.0
	for i in range(angles.size()): escape_gap=maxf(escape_gap,fposmod(angles[(i+1)%angles.size()]-angles[i],TAU))
	times.sort()
	nav_times.sort()
	metrics.crowd={"blocked":blocked,"agents":32,"frames":600,"world_seconds":30,"median_usec":times[300],"p95_usec":times[570],"max_usec":times[-1],"navigation_server_p95_usec":nav_times[570],"navigation_server_max_usec":nav_times[-1],"native_path_queries":queries,"progressed":progressed,"within_5m":close,"peak_within_5m":peak_close,"pressure_frames":pressure_frames,"contact_hits":trial.player.hits,"minimum_body_ratio":nearest,"max_step":max_step,"reverse_steps":reversals,"escape_gap_radians":escape_gap}
	expect(safe and max_step<.12,"32-agent movement stays collision-safe and bounded per step")
	expect(nearest>=.96,"Crowd body clearance prevents overlapping piles")
	# Wide bodies cannot all occupy the front rank. Require a group within cone
	# distance for >=1.5 world seconds and multiple actual contacts, rather than
	# eight bodies within 5m on one arbitrary final frame of native RVO.
	expect(progressed>=28 and pressure_frames>=30 and trial.player.hits>=3,"Crowd detours reach sustained genuine contact pressure, not an exhibit safe spot")
	expect(escape_gap>.8,"A broad escape sector remains outside the approaching crowd")
	expect(reversals<120,"No constant per-frame side flipping in the swarm")
	expect(queries<3900,"Native path work is bounded; targets do not repath every tick")
	expect(times[570]<50000,"Full 32-actor director p95 stays bounded below 50ms on this check host")
	var replay: Dictionary = trial.director.capture_state()
	expect(values_only(replay) and var_to_bytes(replay).size() < ReplayHistory.MAX_PAYLOAD_BYTES, "Full 32-agent replay stays value-only and below the history payload bound")
	var positions: Array[Vector3] = []
	for actor in trial.director.enemies: positions.append(actor.position)
	trial.player.time_controller.force_depletion()
	expect(trial.director.enemies.all(func(actor):return not actor.navigation.avoidance_enabled), "Emergency signal suspends RVO immediately, even without an arena step")
	for i in range(3): await physics_frame
	expect(trial.director.enemies.all(func(actor):return not actor.navigation.avoidance_enabled), "No native avoidance runs while scrub is frozen")
	var charges: int = trial.player.time_controller.charges_remaining
	trial.director.restore_state(replay)
	expect(trial.director.enemies.all(func(actor):return not actor.navigation.avoidance_enabled) and trial.player.time_controller.charges_remaining == charges, "Restore discards future RVO velocities and never refunds time charges")
	trial.player.time_controller.finish_emergency()
	trial.player.time_controller.slow_requested = true
	var slow_bound := 0.0
	for i in range(12):
		trial.player.time_controller.advance(.05)
		var before: Array[Vector3] = []
		for actor in trial.director.enemies: before.append(actor.position)
		trial.director.step(.05 * trial.player.time_controller.world_scale,trial.player)
		for j in range(32): slow_bound=maxf(slow_bound,trial.director.enemies[j].position.distance_to(before[j]))
		await physics_frame
	expect(slow_bound < .021, "Slow crowd/RVO steps remain bounded by current world delta after restore")
	metrics.slow_crowd_max_step = slow_bound
	trial.player.time_controller.slow_requested = false
	# Real raw cutter/piercing/cone components against genuinely moving native
	# actors in an open lane. Nothing rewrites their strokes or freezes targets.
	fresh()
	var nodes: Array=trial.director.spawn_formation(&"curve",[&"blue",&"blue",&"blue"],trial.player,0)
	for i in range(22): await tick(.05,Vector3.ZERO)
	var raw: Array[Vector3]=[]
	for actor in nodes:
		var cable: Array[Vector3]=actor.cable_world_points()
		raw.append(cable[0].lerp(cable[1],.5).move_toward(trial.player.position,.35))
	raw.sort_custom(func(a:Vector3,b:Vector3):return a.x<b.x)
	trial.weapons.select_tool(1)
	trial.weapons.handle_event(button(true),trial.player,raw[0])
	for point in raw: trial.weapons.handle_event(InputEventMouseMotion.new(),trial.player,point)
	trial.weapons.handle_event(button(false),trial.player,raw[-1])
	for i in range(65): await tick(1.0/60,raw[-1])
	var cuts: int=3-trial.director.enemies.size()
	expect(cuts>=2,"Moving native blue curve supports a real raw multi-cut")
	fresh()
	nodes=trial.director.spawn_formation(&"line",[&"yellow",&"yellow",&"yellow"],trial.player,0)
	for i in range(22): await tick(.05,Vector3.ZERO)
	var aim: Vector3=nodes[-1].core_world_position()
	trial.weapons.select_tool(2)
	trial.weapons.handle_event(button(true),trial.player,aim)
	trial.weapons.step(.95,trial.player,aim,nodes,0)
	trial.weapons.handle_event(button(false),trial.player,aim)
	for i in range(60): await tick(1.0/60,aim)
	var kills: int=3-trial.director.enemies.size()
	expect(kills==3,"Moving native yellow file supports one charged piercing pulse")
	fresh()
	nodes=trial.director.spawn_formation(&"cluster",[&"orange",&"orange",&"orange"],trial.player,0)
	for i in range(60): await tick(.05,Vector3.ZERO)
	var center:=Vector3.ZERO
	for actor in nodes: center+=actor.position
	center/=3
	var cluster_width:=0.0
	for actor in nodes: cluster_width=maxf(cluster_width,actor.position.distance_to(center))
	trial.player.position=center+Vector3(0,0,3.5)
	trial.weapons.select_tool(3)
	trial.weapons.handle_event(button(true),trial.player,center)
	for i in range(80): await tick(1.0/60,center)
	var heated: int=3-trial.director.enemies.size()
	expect(cluster_width<3 and heated>=1,"Native orange cluster retains a usable cone/control opportunity")
	metrics.opportunities={"blue_cuts":cuts,"yellow_kills":kills,"orange_heated":heated,"orange_radius":cluster_width}
	finish()
func finish() -> void:
	trial.queue_free()
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"metrics":metrics}))
	quit(0 if failures.is_empty() else 1)

func values_only(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal or value is RID: return false
	if value is Array:
		for item in value:
			if not values_only(item): return false
	if value is Dictionary:
		for key in value:
			if not values_only(key) or not values_only(value[key]): return false
	return true
