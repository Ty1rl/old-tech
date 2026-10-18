extends SceneTree
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-5/exports/round-o/"
var arena: Node3D
var caption: Label
var images: Array[String] = []
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func fresh(tool := 1, detail := true) -> void:
	arena.reset_arena()
	arena.director.clear()
	arena.hud.visible = false
	arena.status_hud.visible = false
	arena.slow_bar.visible = false
	arena.player.position = Vector3(0, .55, 6)
	arena.player.set_visual_tool(tool)
	arena.weapons.select_tool(tool)
	arena.time_controller.auto_advance = false
	if detail:
		arena.player.camera.global_position = Vector3(0, 13, 10)
		arena.player.camera.look_at(Vector3(0, .5, 0))
	else:
		arena.player.camera.position = Vector3(0, 20, 14)
		arena.player.camera.rotation_degrees = Vector3(-55, 0, 0)
func picture(name: String, text: String) -> void:
	caption.text = text
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := name + ".png"
	if root.get_texture().get_image().save_png(OUT + path) == OK: images.append(path)
	else: failures.append("Cannot save " + path)
func cut(enemy: CombatPatternEnemy, index: int) -> void:
	var points := enemy.cable_world_points()
	enemy.receive_attack(&"ring", 36, points[index * 2], {"segment_start":points[index * 2],
		"segment_end":points[index * 2 + 1],"radius":.01,"already_hit":false})
func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	root.get_node("GameState").resume()
	arena.hud.visible = false
	arena.status_hud.visible = false
	arena.slow_bar.visible = false
	var layer := CanvasLayer.new()
	caption = Label.new()
	caption.position = Vector2(20,20)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(caption)
	arena.add_child(layer)
	fresh()
	var loop: CombatPatternEnemy = arena.director.spawn(&"loop", Vector3.ZERO)
	await picture("loop-intact", "Loop · wider, separated blue links · detail view · existing primitives")
	cut(loop, 0)
	loop.step_enemy(1, null)
	cut(loop, 1)
	await picture("loop-two-launch-progress", "Two independent launches · both cuts retained · fixed deadline · stone supports stay")
	loop.step_enemy(6, null)
	await picture("loop-timeout", "Timeout reconnects the cable once · supports and body damage remain consistent")
	fresh()
	var zigzag: CombatPatternEnemy = arena.director.spawn(&"zigzag", Vector3.ZERO)
	await picture("zigzag-intact", "Zigzag · wider blue spans and more separation · unchanged raw cutter input")
	fresh(2)
	var pair: CombatPatternEnemy = arena.director.spawn(&"pair", Vector3.ZERO)
	await picture("pair-a", "Quick shot · square lit A socket · shutter lifted · separated B socket")
	var a := pair.valve_world_position(0)
	pair.receive_attack(&"beam",30,a,{"segment_start":a-Vector3.FORWARD*.1,"segment_end":a+Vector3.FORWARD*.1,"radius":.01})
	await picture("pair-b", "Quick shot response · A dims, B lights and opens · no charged core yet")
	fresh(2)
	var boss: CombatPatternEnemy = arena.director.spawn(&"sequence_boss", Vector3.ZERO)
	for i in range(2):
		var point := boss.valve_world_position(i)
		boss.receive_attack(&"beam",30,point,{"segment_start":point-Vector3.FORWARD*.1,"segment_end":point+Vector3.FORWARD*.1,"radius":.01})
	await picture("charged-core", "Charged finisher · steady round core and halo · paired quick sockets retract")
	fresh(1, false)
	arena.director.spawn_formation(&"curve",[&"blue",&"blue",&"blue"],arena.player,0)
	for i in range(75): arena.director.step(1.0/60,arena.player)
	await picture("moving-blue-curve", "Gameplay camera · gentle curved approach · ordinary steering, variance and an escape side")
	fresh(2, false)
	arena.director.spawn_formation(&"line",[&"yellow",&"yellow",&"yellow"],arena.player,0)
	for i in range(75): arena.director.step(1.0/60,arena.player)
	await picture("moving-yellow-file", "Gameplay camera · moving yellow file · a straight charged pulse can pierce all three")
	fresh(2, false)
	arena.player.position = Vector3(0,.55,0)
	var shooter: CombatEnemy = arena.director.spawn(&"ranged",Vector3(0,0,-8))
	arena.director.step(.01,arena.player)
	arena.player.position.x = 3
	arena.director.step(.5,arena.player)
	await picture("locked-warning", "Full warning stays committed through a dodge · thin translucent guide, no final aim snap")
	arena.director.step(.46,arena.player)
	arena.director._step_projectiles(.25,arena.player)
	await picture("visible-head", "Released projectile · collision-sized bright head remains visible after the warning")
	var result := {"status":"passed" if failures.is_empty() else "failed","checks":images.size(),"failures":failures,"images":images}
	FileAccess.open(OUT+"visuals.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
