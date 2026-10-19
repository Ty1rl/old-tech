extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	var manager := root.get_node("SceneManager")
	var audio := root.get_node("AudioManager")
	manager.developer_tools = false
	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	arena.set_physics_process(false)
	arena.status_hud.readout_mode = 0 # Simulate an old saved "Full" setting.
	arena._update_hud()
	expect(not arena.hud.visible and not arena.slow_bar.visible, "An old Full preference cannot expose release debug overlays")
	arena.time_cue.update_state(.25, false)
	expect(not arena.time_cue.caption.visible, "Time tint has no persistent debug caption in release")
	var before: int = arena.director.enemies.size()
	for key in [KEY_F1, KEY_F5, KEY_F6, KEY_F7, KEY_F9, KEY_BACKSPACE]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		arena._input(event)
		arena._unhandled_input(event)
	expect(arena.director.enemies.size() == before, "Release function keys cannot spawn, clear or start test encounters")
	expect(arena.status_hud.readout_mode == 0, "Release F7 cannot enable debug readouts")
	arena.run_developer_action(&"pack")
	expect(arena.director.enemies.size() == before, "Direct test-action calls also require developer opt-in")
	var settings := manager.push_popup(&"Settings") as Control
	expect(settings.get_node_or_null("%Hud") == null, "Diagnostic readouts have moved out of normal Settings")
	manager.close_popup(&"Settings")
	manager.developer_tools = true
	var popup := manager.push_popup(&"Developer") as Control
	expect(popup != null and not popup.apply_action.disabled, "Developer menu exposes test actions for the current arena")
	expect(popup.action_picker.item_count >= 10 and popup.readout_picker.item_count == 3, "Test actions and diagnostic readouts share Developer options")
	manager.close_popup(&"Developer")
	arena.run_developer_action(&"pack")
	expect(arena.director.enemies.size() > before, "Opt-in test actions still work")
	arena.run_developer_action(&"clear")
	expect(arena.director.enemies.is_empty(), "Developer clear action clears actual enemies")
	var arrived: Array = arena.director.spawn_formation(&"curve", [&"blue", &"ranged", &"ranged"], arena.player, 5)
	expect(arrived.size() == 3, "Mixed formation retains all melee and ranged members")
	var ranged: Array[Node3D] = []
	for enemy in arrived:
		if enemy.kind == &"ranged": ranged.append(enemy)
	if ranged.size() == 2:
		var first: Vector3 = (ranged[0].position - arena.player.position).normalized()
		var second: Vector3 = (ranged[1].position - arena.player.position).normalized()
		expect(first.dot(second) < .85, "Ranged arrivals use different safe flanks instead of one melee clump")
	else:
		expect(false, "Both ranged reinforcements arrive")
	for difficulty in [&"easy", &"hard"]:
		for room in CampaignRooms.definitions(difficulty):
			for wave in room.waves:
				if not wave.get("boss", false): continue
				expect(wave.count >= 7 and wave.max_live <= 8, "Boss escorts provide sustained bounded pressure: " + String(difficulty))
				expect(wave.enemies.has(&"ranged"), "Every boss has some ranged support")
				var boss_count := 0
				for kind in wave.enemies:
					if String(kind).ends_with("_boss"): boss_count += 1
					expect(kind not in [&"pair", &"loop", &"zigzag"], "Boss adds favor small units over large pattern units")
				expect(boss_count == 1, "Only one boss is scheduled per boss wave")
	manager.developer_tools = false
	audio.stop_dialogue()
	audio.set_music_context(&"intro")
	arena.queue_free()
	await create_timer(.35).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
