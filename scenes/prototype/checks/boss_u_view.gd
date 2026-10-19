extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 800)
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena); current_scene = arena
	for i in 4: await process_frame
	arena.set_physics_process(false)
	arena.director.clear()
	arena.player.position = Vector3(0, 0, 6)
	arena.hud.hide(); arena.status_hud.hide()
	root.get_node("AudioManager").stop_dialogue()
	root.get_node("AudioManager").set_music_context(&"intro")
	var out := OS.get_environment("XDG_CACHE_HOME").get_base_dir().path_join("exports/round-u")
	for sample in [[&"sequence_boss", 0, "sequence"], [&"sequence_boss", 0, "sequence-45"], [&"final_boss", 1, "zigzag"], [&"final_boss", 1, "zigzag-cut"], [&"final_boss", 2, "loop"]]:
		arena.director.clear()
		var boss: CombatPatternEnemy = arena.director.spawn(sample[0], Vector3.ZERO)
		boss.debug_set_phase(sample[1])
		boss.facing = Vector3.BACK
		if sample[2] == "sequence-45": boss.facing = boss.facing.rotated(Vector3.UP,PI/4)
		if sample[2] == "zigzag-cut":
			boss.link_mask = 1
			boss._update_warden_visuals()
		boss._update_visual_facing()
		boss.pattern_visual.pose(.9, 0, &"recover", 1)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(sample[2] + ".png"))
	arena.feedback.reset_state(); arena.queue_free()
	await process_frame; await create_timer(.3).timeout
	quit()
