extends SceneTree
const Director = preload("res://scenes/prototype/enemies.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")
var checks := 0
var failures: Array[String] = []
var director: Node3D
var player: Node3D
class PlayerProbe extends Node3D:
	var health := 100.0
	func take_damage(amount: float) -> void: health = maxf(0, health - amount)
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)
func shot(enemy: Node3D, point: Vector3, charge := 0.0) -> Dictionary:
	return enemy.receive_attack(&"beam", 1, point, {"segment_start": point + Vector3.FORWARD * .1,
		"segment_end": point + Vector3.BACK * .1, "charge": charge, "radius": .01})
func open_shell(enemy: Node3D) -> void:
	if enemy.active_pattern() == &"pair":
		shot(enemy, enemy.valve_world_position(0))
		shot(enemy, enemy.valve_world_position(1))
	else:
		var points: Array[Vector3] = enemy.cable_world_points()
		for i in range(points.size() / 2):
			enemy.receive_attack(&"ring", 1, points[i * 2], {"segment_start": points[i * 2],
				"segment_end": points[i * 2 + 1], "radius": .01, "already_hit": i > 0})
func run() -> void:
	director = Director.new()
	root.add_child(director)
	director.cover = preload("res://scenes/prototype/cover.gd").new()
	director.cover.set_rectangles([])
	player = PlayerProbe.new()
	root.add_child(player)
	for kind: StringName in [&"loop_boss", &"sequence_boss", &"final_boss"]:
		director.clear()
		var boss: Node3D = director.spawn(kind, Vector3.ZERO)
		boss.facing = Vector3.FORWARD
		var initial: Dictionary = director.capture_state()
		expect(boss.kind == kind and boss.is_boss(), "Actual boss routes through pattern factory: " + String(kind))
		expect(boss.lesson_state().phases == (4 if kind == &"final_boss" else 3), "Boss reports phase count: " + String(kind))
		var first_links: Array[Vector3] = boss.cable_world_points()
		for phase_index in range(boss.phase_count()):
			expect(boss.phase == phase_index, "Boss entered phase %d: %s" % [phase_index, kind])
			if boss.active_pattern() != &"core": open_shell(boss)
			expect(boss.pattern_open or boss.active_pattern() == &"core", "Correct mechanic exposes boss core: " + String(kind))
			var opened: Dictionary = boss.capture_state()
			shot(boss, boss.core_world_position(), .2)
			expect(boss.phase == phase_index and boss.health > 0 and not boss.core_broken, "Low charge cannot skip boss phase: " + String(kind))
			var result := shot(boss, boss.core_world_position(), 1)
			if phase_index < boss.phase_count() - 1:
				expect(boss.phase == phase_index + 1 and not boss.pattern_visual.sections[phase_index].visible, "Charged finisher removes assembly: " + String(kind))
				if kind == &"loop_boss" and phase_index == 0:
					expect(first_links[0].distance_to(boss.cable_world_points()[0]) > .1, "Repeated loop rearranges real link anchors")
				var next_phase: Dictionary = boss.capture_state()
				boss.restore_state(opened)
				expect(boss.phase == phase_index and boss.pattern_visual.core.visible, "Rewind restores previous exposed core: " + String(kind))
				boss.restore_state(next_phase)
			else:
				expect(result.killed and boss.health <= 0, "Last core finishes boss: " + String(kind))
		director.restore_state(initial)
		boss = director.enemies[0]
		expect(boss.phase == 0 and boss.health == boss.max_health and boss.pattern_visual.sections[0].visible, "Director rewind restores whole boss: " + String(kind))
		boss.debug_set_phase(boss.phase_count() - 1)
		expect(is_equal_approx(boss.health, boss.max_health / boss.phase_count()), "Phase selector restores correct health fraction: " + String(kind))
		for i in range(1000): boss.receive_attack(&"beam", 36, boss.position)
		expect(boss.health <= 0, "Ordinary body damage remains a poor but complete route: " + String(kind))
	# A shooter locks its aim before firing and spends only world time.
	director.clear()
	player.position = Vector3.ZERO
	player.health = 100
	var ranged: Node3D = director.spawn(&"ranged", Vector3(0, 0, -8))
	director.step(.01, player)
	expect(ranged.kind == &"ranged" and ranged.attack_phase == &"windup" and ranged.ranged_warning.visible, "Ranged has a visible windup")
	var aim: Vector3 = ranged.ranged_aim
	var windup: Dictionary = director.capture_state()
	player.position.x = 3
	director.step(.5, player)
	expect(ranged.ranged_aim == aim and director.projectiles.is_empty(), "Windup locks aim and gives time to dodge")
	director.step(0, player)
	expect(is_equal_approx(ranged.attack_timer, .45), "Frozen world stops ranged windup")
	director.restore_state(windup)
	for i in range(100): director.step(.005, player)
	expect(is_equal_approx(ranged.attack_timer, .45) and director.projectiles.is_empty(), "Slow small ticks advance the same world-time windup")
	director.step(.46, player)
	expect(director.projectiles.size() == 1 and ranged.attack_phase == &"recover", "Completed windup launches one bounded projectile and recovers")
	var start: Vector3 = director.projectiles[0].position
	director.step(.1, player)
	expect(is_equal_approx(start.distance_to(director.projectiles[0].position), .75), "Projectile uses world velocity")
	var flying: Dictionary = director.capture_state()
	var encoded := var_to_bytes(flying)
	expect(encoded.size() > 0 and bytes_to_var(encoded).projectiles.size() == 1, "Projectiles serialize without node references")
	director.step(.4, player)
	director.restore_state(flying)
	expect(director.projectiles == flying.projectiles and ranged.attack_phase == &"recover", "Rewind restores projectile position and shooter recovery exactly")
	director.clear()
	expect(director.projectiles.is_empty(), "Room clear removes hostile projectiles")
	# Swept collision respects cover ordering, player dodge, damage and lifetime.
	director.cover.set_rectangles([Rect2(-1, -4, 2, 1)])
	player.position = Vector3.ZERO
	player.health = 100
	director.launch_projectile(Vector3(0, 0, -6), Vector3.BACK, 10)
	director.step(1, player)
	expect(player.health == 100 and director.projectiles.is_empty(), "Cover absorbs swept projectile before player")
	director.cover.set_rectangles([])
	director.launch_projectile(Vector3(0, 0, -6), Vector3.BACK, 10)
	director.step(1, player)
	expect(player.health == 90 and director.projectiles.is_empty(), "Swept projectile hits player without tunneling")
	director.launch_projectile(Vector3(0, 0, -6), Vector3.BACK, 10)
	player.position.x = 2
	director.step(1, player)
	expect(player.health == 90, "Sidestepping the locked shot avoids damage")
	director.clear()
	for i in range(40): director.launch_projectile(Vector3.ZERO, Vector3.FORWARD, 10)
	expect(director.projectiles.size() == 24, "Hostile projectiles have a hard live cap")
	director.step(6.1, null)
	expect(director.projectiles.is_empty(), "Projectiles expire in bounded world time")
	# Boss attacks use distinct footprints, locked facing, and recovery.
	for kind: StringName in [&"loop_boss", &"sequence_boss", &"final_boss"]:
		director.clear()
		player.health = 100
		player.position = Vector3(0, 0, -3)
		var boss: Node3D = director.spawn(kind, Vector3.ZERO)
		boss.facing = Vector3.FORWARD
		boss.step_enemy(.01, player)
		expect(boss.attack_phase == &"windup" and boss.pattern_visual.warning.visible, "Boss warns before threat: " + String(kind))
		var locked: Vector3 = boss.facing
		player.position.x = 1
		boss.step_enemy(.5, player)
		expect(boss.facing == locked and player.health == 100, "Boss locks danger direction during windup: " + String(kind))
		boss.step_enemy(.61, player)
		boss.step_enemy(.19, player)
		expect(boss.attack_phase == &"recover" and boss.attack_timer >= 2, "Boss grants stationary recovery: " + String(kind))
		if kind == &"loop_boss": expect(player.health < 100, "Loop boss radial attack matches its marked circle")
		else: expect(director.projectiles.size() >= 3, "Sequence boss fan attack spawns dodgeable bolts: " + String(kind))
	# Model part removal is immediate and derived again on restore.
	director.clear()
	var blue: Node3D = director.spawn(&"blue", Vector3.ZERO)
	var intact: Dictionary = blue.capture_state()
	expect(blue.part_visual.split_companion.size() > 0 and blue.part_visual.cable_marker.visible, "Blue connector identifies a physical companion assembly")
	var links: Array[Vector3] = blue.cable_world_points()
	blue.receive_attack(&"ring", 1, links[0], {"segment_start": links[0], "segment_end": links[1]})
	expect(not blue.part_visual.cable_marker.visible and not blue.part_visual.split_companion[0].visible, "Cut connector and severed companion physically disappear")
	blue.restore_state(intact)
	expect(blue.part_visual.cable_marker.visible and blue.part_visual.split_companion[0].visible, "Rewind restores connector and split companion")
	var guard: Node3D = director.spawn(&"front_guard", Vector3(3, 0, 0))
	var armored: Dictionary = guard.capture_state()
	guard.receive_attack(&"cone", 1, guard.position, {"dt": 1})
	expect(not guard.part_visual.plate.visible and guard.part_visual.core_marker.visible, "Heat physically removes orange and reveals bright yellow")
	var bare: Dictionary = guard.capture_state()
	guard.restore_state(armored)
	expect(guard.part_visual.plate.visible and not guard.part_visual.core_marker.visible, "Rewind restores orange armor and hides closed core")
	guard.restore_state(bare)
	expect(not guard.part_visual.plate.visible and guard.part_visual.core_marker.material_override.no_depth_test, "Bare armor stays absent and yellow remains visible from every angle")
	if DisplayServer.get_name() != "headless": await preview()
	director.free()
	player.free()
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func preview() -> void:
	director.clear()
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(11, 17, 23)
	camera.look_at(Vector3(0, 1, 0))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 58
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.4
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("20272d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a5b5bf")
	environment.environment.ambient_light_energy = .65
	stage.add_child(environment)
	var floor_node := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(30, .1, 23)
	floor_node.mesh = floor_mesh
	floor_node.position.y = -.1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("3e484c")
	floor_node.material_override = material
	stage.add_child(floor_node)
	var roster: Array[Node3D] = []
	var kinds := [&"loop_boss", &"sequence_boss", &"final_boss", &"blue", &"yellow", &"front_guard", &"ranged"]
	var positions := [Vector3(-7, 0, -4), Vector3(0, 0, -4), Vector3(7, 0, -4), Vector3(-6, 0, 4), Vector3(-2, 0, 4), Vector3(2, 0, 4), Vector3(6, 0, 4)]
	for i in range(kinds.size()):
		var enemy: Node3D = director.spawn(kinds[i], positions[i])
		enemy.facing = Vector3.BACK
		roster.append(enemy)
		var label := Label3D.new()
		label.text = String(kinds[i]).replace("_", " ").to_upper()
		label.position = positions[i] + Vector3(0, .1, 2.4)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 32
		stage.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	var destination := "/home/mattlongname/game-jams/state/old-tech-jam-1/exports/render"
	DirAccess.make_dir_recursive_absolute(destination)
	root.get_texture().get_image().save_png(destination + "/enemies-l-intact.png")
	for i in range(3):
		roster[i].debug_set_phase(1)
		roster[i].attack_phase = &"windup"
		roster[i]._update_warden_visuals()
	roster[3].cable_cut = true
	roster[3]._update_warden_visuals()
	roster[5].plate_broken = true
	roster[5]._update_warden_visuals()
	roster[6].ranged_aim = Vector3.BACK
	roster[6].attack_phase = &"windup"
	roster[6]._sync_ranged_visual()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination + "/enemies-l-open.png")
	stage.queue_free()
