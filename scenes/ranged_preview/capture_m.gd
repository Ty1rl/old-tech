extends SceneTree

const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-6/exports/round-m/"
const PASS := "pass-b"
var arena: Node3D
var caption: Label
var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)


func picture(name: String, text: String) -> void:
	caption.text = text
	caption.visible = name != "repair-flight"
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if name == "repair-flight":
		var heads: Array = arena.director.repair_head_projections()
		expect(heads.size() == 3, "all three projected bolt heads survive opaque repair prop occlusion")
		for head: Dictionary in heads:
			var point: Vector2 = head.point * Vector2(image.get_size()) / root.get_visible_rect().size
			var color := image.get_pixelv(Vector2i(point.round()))
			expect(color.r > .85 and color.g > .65 and color.b > .4, "actual repair capture contains the bright head at its projected position")
	expect(image.save_png(OUT + PASS + "-" + name + ".png") == OK, "capture " + name)
	var points: Array = []
	for shot: Dictionary in arena.director.projectiles:
		var screen: Vector2 = arena.player.camera.unproject_position(shot.position)
		points.append({"world": [shot.position.x, shot.position.y, shot.position.z], "screen": [screen.x, screen.y],
			"speed": shot.velocity.length(), "radius": shot.radius})
	samples.append({"capture":name, "shots":points})


func reset() -> void:
	arena.reset_arena()
	arena.director.clear()
	arena.player.health = 100
	arena.player.position = Vector3(0, .55, 0)
	arena.hud.visible = false
	arena.slow_bar.visible = false
	arena.status_hud.visible = false
	arena.feedback.muted = true


func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	root.get_node("GameState").resume()
	var canvas := CanvasLayer.new()
	caption = Label.new()
	caption.position = Vector2(22, 24)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(caption)
	arena.add_child(canvas)
	reset()
	var shooter: Node3D = arena.director.spawn(&"ranged", Vector3(0, 0, -8))
	arena.director.step(.01, arena.player)
	await picture("warning", "Hostile shot / committed lane / move aside")
	arena.director.step(.96, arena.player)
	arena.director.step(.18, arena.player)
	expect(arena.director.projectiles.size() == 1, "actual shooter launches a visible projectile")
	await picture("flight", "Red rim, ivory head, short trail / movement is the defense")
	var start: Vector3 = arena.player.position
	for frame in range(35):
		arena.player.position.x += 6.0 / 60
		arena.director.step(1.0 / 60, arena.player)
	expect(arena.player.health == 100 and arena.player.position.distance_to(start) > 3, "ordinary lateral movement dodges the actual shot")
	await picture("dodge", "Sidestep the committed shot / no homing or new defense ability")
	reset()
	var boss: Node3D = arena.director.spawn(&"final_boss", Vector3(0, 0, -8))
	boss.facing = Vector3.BACK
	boss._step_part_attack(.01, arena.player, 8)
	await picture("boss-warning", "Boss fan / three fixed lanes / wide gaps")
	boss._step_part_attack(1.11, arena.player, 8)
	boss._step_part_attack(.19, arena.player, 8)
	arena.director._step_projectiles(.55, arena.player)
	expect(arena.director.projectiles.size() == 3, "actual boss emits only three committed bolts")
	await picture("boss-flight", "Boss fan / red and ivory threats stay distinct from weakpoints")
	# Use the real baseline repair popup and perspective, with no scene edits.
	arena.equipment.spend(&"beam", 10)
	var popup: Control = root.get_node("SceneManager").push_popup(&"Repair", {"equipment":arena.equipment,"tool":&"beam"})
	await process_frame
	await process_frame
	expect(popup != null and popup.visible, "real transparent repair overlay is present")
	await picture("repair-flight", "Repair overlay / hostile shots remain visible in the surrounding world")
	expect(arena.director._repair_head_layer.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE, "repair head rendering never intercepts gesture input")
	root.get_node("SceneManager").push_popup(&"Settings")
	await process_frame
	expect(arena.director.repair_head_projections().is_empty(), "settings above repair hide the projected head pass")
	root.get_node("SceneManager").pop_popup()
	await process_frame
	await process_frame
	expect(arena.director.repair_head_projections().size() == 3, "closing settings restores repair head visibility")
	root.get_node("SceneManager").pop_popup()
	await process_frame
	await process_frame
	root.get_node("GameState").resume()
	expect(arena.director.repair_head_projections().is_empty(), "projected head pass clears when repair closes")
	reset()
	arena.director.launch_projectile(Vector3(0, 1, -2), Vector3.BACK, 10)
	arena.director._step_projectiles(.25, arena.player)
	expect(arena.player.health == 90, "actual projectile damage produces the impact cue")
	await picture("damage", "Hit feedback / warm red impact ring and low damage cue")
	var report := {"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures,
		"projection":"perspective", "fov":arena.player.camera.fov, "samples":samples}
	var file := FileAccess.open(OUT + "capture-" + PASS + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
