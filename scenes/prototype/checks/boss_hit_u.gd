extends SceneTree
const AdaptedAim = preload("res://scenes/prototype/checks/boss_aim_adapter_u.gd")
var checks := 0
var failures: Array[String] = []
var arena: Node3D
var boss: CombatPatternEnemy
var flash: FocusedFlash
var pristine: Dictionary
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message); printerr("FAIL: " + message)
func reset(angle: float = 0) -> void:
	boss.restore_state(pristine)
	boss.facing = Vector3.BACK.rotated(Vector3.UP, angle)
	boss._update_visual_facing()
	flash.reset_state(); arena.equipment.reset_state()
func shoot(aim: Vector3, charge: float = 0, targets: Array = [], turn_rate: float = 0) -> void:
	flash.reset_state(); arena.equipment.reset_state()
	flash.press(); flash.charge_time = charge * flash.settings.charge_time
	flash.release(arena.player.position, aim, arena.player.position + Vector3.UP)
	var facing := boss.facing
	var direction: Vector2 = flash.pulses[0].dir
	for frame in 45:
		if turn_rate != 0:
			boss.facing = facing.rotated(Vector3.UP, turn_rate * minf((frame + 1)/60.0, .12))
			boss._update_visual_facing()
		flash.step(1.0/60, 1.0/60, [boss] if targets.is_empty() else targets, Vector3.ZERO)
		if frame == 0 and not flash.pulses.is_empty():
			expect(flash.pulses[0].dir == direction, "Traveling shot remains straight without target snapping")
func ray(point: Vector3, charge: float = 0) -> Dictionary:
	return boss.receive_attack(&"beam", 30, point, {"segment_start":point-Vector3(0,0,.05), "segment_end":point+Vector3(0,0,.05), "radius":.01, "charge":charge})
func run() -> void:
	root.size = Vector2i(1280, 800)
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena); current_scene = arena
	for i in 4: await process_frame
	arena.set_physics_process(false); arena.director.clear()
	arena.weapons.select_tool(2); flash = arena.weapons.flash
	boss = arena.director.spawn(&"sequence_boss", Vector3.ZERO)
	pristine = boss.capture_state()
	var edge_hits := 0
	var integrated_edge_hits := 0
	var unadapted_edge_misses: Array = []
	for player_x in [-3.0, 0.0, 3.0]:
		arena.player.position = Vector3(player_x, 0, 6)
		for angle in [0.0, PI/4, PI/2, 3*PI/4, PI]:
			var offsets := [Vector3.ZERO]
			for x in [-.42, .42]:
				for y in [-.42, .42]: offsets.append(Vector3(x,y,-.15))
			for offset: Vector3 in offsets:
				reset(angle)
				var point := boss.valve_world_position(0) + boss.visual_root.basis * offset
				var pixel: Vector2 = arena.player.camera.unproject_position(point)
				shoot(arena.floor_aim(pixel))
				if boss.pair_progress == 1: edge_hits += 1
				else: unadapted_edge_misses.append({"player_x":player_x,"angle":angle,"offset":str(offset)})
				# Check the exact proposed one-call camera adapter without editing
				# another owner's AimAssist. Aim remains on the clicked surface.
				reset(angle)
				var surface: Variant = AdaptedAim.target(pixel,arena.player.camera,[boss],2,arena.player.position)
				var adapted: Vector3 = surface if surface != null else arena.floor_aim(pixel)
				shoot(adapted)
				expect(boss.pair_progress == 1, "Visible A center/edge with exact surface adapter from player %.0f angle %.2f offset%s" % [player_x,angle,offset])
				if boss.pair_progress == 1: integrated_edge_hits += 1
	arena.player.position = Vector3(0,0,6)
	reset()
	var away: Vector2 = arena.player.camera.unproject_position(boss.valve_world_position(0)) + Vector2(150,0)
	expect(boss.visible_flash_aim(arena.player.camera.project_ray_origin(away),arena.player.camera.project_ray_normal(away)) == null, "Surface adapter rejects pixels away from shown socket")
	expect(AdaptedAim.target(away,arena.player.camera,[boss],2,arena.player.position) == null, "Proposed integration does not increase arbitrary snap range")
	for angle in [0.0, PI/4, PI/2, PI]:
		reset(angle)
		ray(boss.valve_world_position(1))
		expect(boss.pair_progress == 0 and not boss.pattern_open, "Closed B cannot start sequence")
		shoot(boss.valve_world_position(0))
		expect(boss.pair_progress == 1 and not boss.pattern_open, "A opens only B")
		shoot(boss.valve_world_position(1))
		expect(boss.pattern_open and boss.phase == 0, "B opens core without skipping finisher")
		shoot(boss.core_world_position(), .2)
		expect(boss.phase == 0, "Uncharged core cannot advance boss")
		shoot(boss.core_world_position(), 1)
		expect(boss.phase == 1 and not boss.pattern_visual.sections[0].visible, "Charged core removes correct phase assembly")
	reset()
	ray(boss.valve_world_position(0)); ray(boss.valve_world_position(0))
	expect(boss.pair_progress == 0 and not boss.pattern_open, "Wrong A after A resets pair")
	reset()
	var outside := boss.valve_world_position(0) + Vector3(boss.yellow_hit_radius() + .08, 0, 0)
	var missed := ray(outside)
	expect(not missed.connected and boss.pair_progress == 0, "Ray outside explicit edge tolerance misses")
	for angle in [0.0, PI/4, PI/2]:
		reset(angle);shoot(boss.valve_world_position(0),0,[],1.5)
		expect(boss.pair_progress == 1, "Modest rotation during actual projectile travel retains overlapping target hit")
	reset(PI/4)
	var origin: Vector3 = arena.player.position
	var aim := boss.valve_world_position(0)
	var direction := Vector3(aim.x-origin.x,0,aim.z-origin.z).normalized()
	var other = arena.director.spawn(&"target", origin + direction*11)
	var other_hp: float = other.health
	shoot(aim,0,[boss,other])
	expect(boss.pair_progress == 1 and other.health == other_hp, "Quick shot consumes at visible yellow before target behind it")
	reset(PI/4)
	shoot(boss.valve_world_position(0),1,[boss,other])
	expect(boss.pair_progress == 1 and other.health < other_hp, "Charged piercing retains downstream hit")
	reset(PI/4)
	var wall = load("res://scenes/prototype/cover.gd").new([Rect2(-4,2.7,8,.4)])
	flash.cover = wall
	var hp := boss.health
	shoot(boss.valve_world_position(0),1)
	expect(boss.pair_progress == 0 and boss.health == hp, "Cover blocks visible target and piercing shot")
	flash.cover = arena.cover
	# Blue render endpoints, radius and cut query share the same authoritative
	# geometry in every rotated loop and the final zigzag/loop phases.
	arena.director.clear()
	boss = arena.director.spawn(&"final_boss", Vector3.ZERO)
	for phase in [1,2]:
		boss.debug_set_phase(phase)
		# Actual cutter input/path/travel through the same Arena weapon owner;
		# avoid relying solely on direct receive_attack queries for blue progress.
		boss.facing = Vector3.BACK;boss._update_visual_facing()
		var path: Array[Vector3] = []
		var physical := boss.cable_world_points()
		for i in range(physical.size()/2): path.append((physical[2*i]+physical[2*i+1])*.5)
		if phase == 2: path.append(path[0])
		var w: Node3D = arena.weapons
		w.select_tool(1);arena.equipment.reset_state()
		var down := InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true
		w.handle_event(down,arena.player,path[0])
		for point in path:
			var move := InputEventMouseMotion.new();move.button_mask=MOUSE_BUTTON_MASK_LEFT
			w.handle_event(move,arena.player,point)
		var up := InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false
		w.handle_event(up,arena.player,path[-1])
		for frame in 180:
			w.step(1.0/60,arena.player,path[-1],[boss],1.0/60)
			boss.step_enemy(1.0/60,null)
		expect(boss.pattern_open, "Actual traveling cutter opens final boss blue phase")
		expect(arena.equipment.remaining(&"ring") == arena.equipment.capacity(&"ring")-1, "Physical boss pattern costs one cutter launch")
		boss.debug_set_phase(phase)
		boss.facing = Vector3.BACK.rotated(Vector3.UP,.6);boss._update_visual_facing()
		var points := boss.cable_world_points()
		for i in boss.pattern_visual.links.size():
			var link: MeshInstance3D = boss.pattern_visual.links[i]
			var half: float = link.mesh.height*.5
			var a := link.global_position - link.global_basis.y*half
			var b := link.global_position + link.global_basis.y*half
			expect(a.distance_to(points[2*i]) < .001 and b.distance_to(points[2*i+1]) < .001, "Shown blue endpoints equal cuttable span")
			expect(is_equal_approx(link.mesh.top_radius, .38) and is_equal_approx(points[2*i].y, 1.65), "Boss blue has explicit raised/thicker physical geometry")
			expect(link.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and link.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Blue readability uses cached unlit opaque material")
			boss.receive_attack(&"ring",36,points[2*i],{"segment_start":points[2*i],"segment_end":points[2*i+1],"radius":.01,"already_hit":true})
			expect(not link.visible and boss.pattern_visual.cut_ends[i].visible, "Cut cable leaves an obvious gap/stubs")
			expect(boss.pattern_visual.link_sections[i].visible, "Cut preserves support instead of phantom detachment")
		expect(boss.pattern_open, "All physical blue spans open phase")
		var saved := boss.capture_state()
		ray(boss.core_world_position(),1)
		expect(boss.phase == phase+1 and not boss.pattern_visual.sections[phase].visible, "Blue finisher removes only intended assembly")
		boss.restore_state(saved)
		expect(boss.phase == phase and boss.pattern_open, "Rewind restores phase geometry and opening")
	for phase in range(3):
		boss.configure(&"loop_boss", Vector3.ZERO,53);boss.debug_set_phase(phase)
		boss.facing = Vector3.BACK.rotated(Vector3.UP,.4);boss._update_visual_facing()
		var points := boss.cable_world_points()
		for i in 4:
			var link: MeshInstance3D = boss.pattern_visual.links[i]
			expect(link.global_position.distance_to((points[2*i]+points[2*i+1])*.5) < .001, "Rotated boss loop matches physical links")
	root.get_node("AudioManager").stop_dialogue();root.get_node("AudioManager").set_music_context(&"intro")
	arena.feedback.reset_state();arena.queue_free()
	await process_frame;await create_timer(.3).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"projected_edge_hits_without_adapter":edge_hits,"projected_edge_hits_with_adapter":integrated_edge_hits,"projected_edge_samples":75,"external_aim_adapter_needed":unadapted_edge_misses}))
	quit(0 if failures.is_empty() else 1)
