extends SceneTree
const OUT := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-7/exports/round-m"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	create_timer(15,true).timeout.connect(func(): quit(1))
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena); current_scene = arena
	await process_frame; await process_frame
	arena.set_physics_process(false)
	var batches: Array[int] = []
	for batch in range(5):
		var start := Time.get_ticks_usec()
		for i in range(3000):
			arena.status_hud.update_status(arena.player,arena.weapons,arena.equipment)
			arena.status_hud.set_combat_hint(false)
			arena.status_hud.update_timeline(arena.history,0,"",12)
		batches.append(Time.get_ticks_usec()-start)
	var font := ThemeDB.fallback_font
	var start := Time.get_ticks_usec()
	for i in range(18000):
		font.get_string_size("Flash · full · E repair",HORIZONTAL_ALIGNMENT_LEFT,-1,13)
	var font_usec := Time.get_ticks_usec()-start
	var cached_usec := -1
	if arena.status_hud.has_method("_text_width"):
		start = Time.get_ticks_usec()
		for i in range(18000): arena.status_hud._text_width("Flash · full · E repair",13)
		cached_usec = Time.get_ticks_usec()-start
	var phase := FileAccess.get_file_as_string(OUT+"/phase.txt").strip_edges()
	var data := {"status":"passed","checks":1,"failures":[],"batches_usec_per_3000":batches,"font_width_usec_per_18000":font_usec,"cached_width_usec_per_18000":cached_usec}
	var file := FileAccess.open(OUT+"/"+phase+"-profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  ")+"\n")
	print(JSON.stringify(data)); quit(0)
