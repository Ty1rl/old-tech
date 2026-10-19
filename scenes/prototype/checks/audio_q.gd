extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var manager := root.get_node("AudioManager")
	manager.begin_run()
	var saved: Dictionary = root.get_node("GameState").preferences()
	root.get_node("GameState").set_setting("sound", true)
	root.get_node("GameState").set_setting("voice_volume", .8)
	var count := 0
	for event in manager.library.clips:
		for clip: AudioStream in manager.library.clips[event]:
			count += 1
			expect(clip is AudioStreamMP3 and clip.get_length() > .1, "Recorded voice decodes: " + String(event))
	expect(count == 37, "All 37 supplied dialogue recordings are in the runtime library")
	var voice_bus := AudioServer.get_bus_index(&"Voice")
	expect(voice_bus >= 0 and manager.voice.bus == &"Voice", "Speech has its own bus")
	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(voice_bus, record)
	record.set_recording_active(true)
	manager.lesson(&"shot")
	await create_timer(.4).timeout
	record.set_recording_active(false)
	var recording := record.get_recording()
	expect(manager.current_event == &"tutorial.shot" and manager.voice.get_playback_position() > .1,
		"Actual recorded tutorial starts and advances on the native mixer")
	expect(recording != null and recording.data.size() > 1000,
		"Native voice bus produces captured PCM")
	AudioServer.remove_bus_effect(voice_bus, AudioServer.get_bus_effect_count(voice_bus)-1)
	expect(not manager.say(&"protagonist.under_pressure"), "Barks cannot interrupt teaching")
	manager.stop_dialogue()
	manager._bark_cooldown = 0
	expect(manager.say(&"protagonist.repair_started"), "Repair bark plays when speech is idle")
	manager.stop_dialogue()
	expect(not manager.say(&"protagonist.repair_started"), "Incidental speech cooldown prevents repetition")
	manager.say(&"boss.final_boss.entrance", 3)
	expect(manager.voice.pitch_scale < 1 and manager.current_event == &"boss.final_boss.entrance", "Boss entrance uses its own recorded line/register")
	manager.begin_run()
	var arena: Node3D = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena); current_scene = arena
	await process_frame;await physics_frame
	arena.set_physics_process(false)
	arena._physics_process(2.1)
	arena.player.position = arena.museum.pickup_position + Vector3.UP * .55
	arena._physics_process(.02)
	expect(manager.current_event == &"tutorial.shot", "Actual campaign demonstration requests the correct voice event")
	var supplied := 0
	for cue: CombatAudioCue in arena.feedback.cue_library.cues:
		if "/supplied/" in cue.stream.resource_path:
			supplied += 1
			expect(cue.stream is AudioStreamMP3 and cue.stream.get_length() > .05, "Supplied effect decodes: " + String(cue.id))
	expect(supplied >= 22, "All supplied effects replace their generated fallback cues")
	for id in [&"ring_loop", &"charge_loop", &"cone_loop", &"clock_loop", &"scrub_older", &"scrub_newer", &"time_low_loop"]:
		expect(arena.feedback.samples[id].loop, "Supplied native loop metadata: " + String(id))
	arena.tutorial.dismiss();arena.lesson_demo.cancel()
	arena.time_controller.try_spend(85)
	arena.feedback.step(.1, .1, 1, false, 0, arena.weapons, arena.equipment)
	expect(arena.feedback._loops[&"clock_loop"].player.stream == arena.feedback.samples[&"time_low_loop"], "Low time uses supplied warning texture without an extra player")
	var before: Array = manager.played_events.duplicate()
	var snapshot: Dictionary = arena.capture_state()
	arena._restore_world(snapshot, true)
	expect(manager.played_events == before, "World history preview never replays dialogue")
	manager.stop_dialogue()
	await create_timer(.12).timeout
	arena.feedback.reset_state();arena.queue_free()
	await process_frame;await create_timer(.3).timeout
	for key in saved: root.get_node("GameState").set_setting(key,saved[key])
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
