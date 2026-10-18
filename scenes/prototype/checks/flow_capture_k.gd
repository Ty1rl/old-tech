extends SceneTree

const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-6/exports/round-k/"
const PASS := "pass-b"
var arena: Node3D
var title: Label
var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []


func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func button(down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	return event


func fresh(tool: int) -> void:
	arena.reset_arena()
	arena.director.clear()
	arena.player.position = Vector3(0, .55, 0)
	arena.player.health = 10000
	arena.weapons.select_tool(tool)
	arena.player.set_visual_tool(tool)
	arena.player.model.basis = Basis.looking_at(Vector3.FORWARD)
	arena.player.camera.size = 22
	arena.status_hud.visible = false
	arena.hud.visible = false
	arena.slow_bar.visible = false


func picture(name: String, caption: String) -> void:
	title.text = caption
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(OUT + name + ".png") == OK, "capture " + name)


func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	root.get_node("GameState").resume()
	var canvas := CanvasLayer.new()
	title = Label.new()
	title.position = Vector2(24, 25)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(title)
	arena.add_child(canvas)
	fresh(1)
	var nodes: Array = arena.director.spawn_formation(&"curve", [&"blue", &"blue", &"blue", &"blue", &"blue"], arena.player)
	await picture(PASS + "-blue-warning", "Blue cohort / arrival warning / keep an escape side")
	for i in range(20):
		arena.director.step(.1, arena.player)
		if i % 5 == 0:
			var points: Array = []
			for node in nodes: points.append([node.position.x, node.position.z])
			samples.append({"world_seconds": float(i + 1) * .1, "blue_positions": points})
	await picture(PASS + "-blue-approach", "Blue cohort / moving curve / one sweeping cut")
	var raw: Array[Vector3] = []
	for node in nodes:
		var cable: Array = node.cable_world_points()
		var midpoint: Vector3 = (cable[0] + cable[-1]) * .5
		# A deliberate drawn lead for flight time, rather than freezing targets
		# during the preview. No targeting or path correction exists in weapons.
		raw.append(midpoint.move_toward(Vector3(0, midpoint.y, 0), .35))
	raw.sort_custom(func(a: Vector3, b: Vector3): return a.x < b.x)
	arena.weapons.handle_event(button(true), arena.player, raw[0] - Vector3.RIGHT * .25)
	for point in raw:
		var move := InputEventMouseMotion.new()
		arena.weapons.handle_event(move, arena.player, point)
	arena.weapons._rebuild_visuals(arena.player, raw[-1])
	await picture(PASS + "-cutter-guide", "Cutter / sweeping curve with a slight lead")
	arena.weapons.handle_event(button(false), arena.player, raw[-1] + Vector3.RIGHT * .25)
	for i in range(45):
		arena.weapons.step(1.0 / 60, arena.player, raw[-1], nodes)
		arena.director.step(1.0 / 60, arena.player)
	var cut_count := 0
	for node in nodes:
		if node.cable_cut: cut_count += 1
	expect(cut_count >= 3, "moving blue cohort supports multi-cut sweep")
	await picture(PASS + "-blue-cut", "Cutter / one sweep through a moving cohort")
	fresh(2)
	nodes = arena.director.spawn_formation(&"line", [&"yellow", &"yellow", &"yellow"], arena.player)
	await picture(PASS + "-yellow-line", "Yellow file / line up a charged piercing shot")
	var aim: Vector3 = nodes[-1].position
	arena.weapons.handle_event(button(true), arena.player, aim)
	arena.weapons.step(.9, arena.player, aim, nodes, 0)
	expect(arena.weapons.presentation.pierce_ready and arena.weapons.beam_pulses.is_empty(), "ready aperture, no pre-release beam")
	await picture(PASS + "-charge-ready", "PIERCE READY / release to fire")
	arena.weapons.handle_event(button(false), arena.player, aim)
	arena.weapons.step(.22, arena.player, aim, nodes)
	await picture(PASS + "-pierce-flight", "Charged pulse / straight through intersected enemies")
	arena.weapons.step(.1, arena.player, aim, nodes)
	var kills := 0
	for node in nodes:
		if node.health <= 0: kills += 1
	expect(kills == 3, "charged line shot finishes all three yellow cores")
	fresh(3)
	nodes = arena.director.spawn_formation(&"cluster", [&"orange", &"orange", &"orange"], arena.player)
	for i in range(30): arena.director.step(.1, arena.player)
	await picture(PASS + "-orange-cluster", "Orange pack / compact approach / cone opportunity")
	var report := {"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures, "motion":samples, "cut_count":cut_count, "pierce_kills":kills}
	var f := FileAccess.open(OUT + "capture-" + PASS + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
