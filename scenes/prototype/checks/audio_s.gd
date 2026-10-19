extends SceneTree
var checks := 0
var failures: Array[String] = []
var terminals: Array = []
var manager: Node
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)
func terminal(event: StringName, interrupted: bool) -> void:
	terminals.append([event, interrupted])
func reset() -> void:
	manager.begin_run()
	# Individual event probes bypass startup silence; test the real delay below.
	manager._bark_cooldown = 0
	terminals.clear()
func run() -> void:
	manager = root.get_node("AudioManager")
	var state := root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	for pair in [["sound", true], ["volume", .8], ["voice_volume", .9]]: state.set_setting(pair[0], pair[1])
	manager.speech_finished.connect(terminal)
	var texts := {
		&"narration.intro": "An ancient device has turned exhibits into monsters. Survive with cobbled-together old tech and time borrowed from your future self.",
		&"tutorial.time_meter": "Taking damage, slowing time, and repairing drain your reserve. Find moments to let it recharge.",
		&"tutorial.pickup": "Walk towards the new item."}
	for event in texts:
		expect(manager.library.transcripts.get(event) == texts[event], "Exact supplier-confirmed transcript: " + String(event))
		var clip: AudioStreamMP3 = manager.library.clips[event][0]
		expect(clip != null and clip.get_length() > 1 and not clip.loop, "New speech decodes without looping: " + String(event))
	reset()
	manager.begin_run()
	expect(not manager.say(&"protagonist.repair_started"), "A new run starts with quiet protagonist audio")
	manager._process(59.9)
	expect(not manager.say(&"protagonist.under_pressure"), "Startup silence lasts 60 seconds")
	manager._process(.2)
	expect(manager.say(&"protagonist.under_pressure") and manager.voice.volume_db == -8, "After startup delay, protagonist plays 2 dB below other speech")
	manager.stop_dialogue()
	manager.lesson(&"shot")
	expect(manager.voice.volume_db == -6, "Tutorial retains its original voice level after a protagonist line")
	reset()
	manager.lesson(&"shot")
	expect(manager.is_speaking(&"tutorial.shot") and not manager.is_speaking(&"tutorial.time_meter") and manager._queue.is_empty(), "Shot has no obsolete automatic reserve explanation")
	reset()
	expect(manager.say(&"tutorial.pickup", 3), "Pickup request accepted")
	await create_timer(.35).timeout
	expect(manager.voice.get_playback_position() > .05 and manager.instruction_busy(), "Actual pickup recording advances")
	await create_timer(manager.voice.stream.get_length() + .3).timeout
	expect(terminals == [[&"tutorial.pickup", false]] and not manager.instruction_busy(), "Natural pickup completion is a single non-interrupted terminal")
	expect(manager._bark_cooldown > 18 and not manager.say(&"protagonist.under_pressure"), "Natural tutorial completion leaves a quiet interval before chatter")
	reset()
	manager.say(&"tutorial.time_meter", 3)
	manager.say(&"tutorial.pickup", 2)
	manager.stop_dialogue()
	expect(terminals == [[&"tutorial.time_meter", true], [&"tutorial.pickup", true]], "Skip cancels active and queued teaching with interrupted=true")
	reset()
	manager.play_intro()
	await create_timer(.2).timeout
	expect(manager.voice.get_playback_position() > .1 and manager.voice.pitch_scale == 1, "New intro plays natively at normal voice pitch")
	manager.stop_dialogue()
	var voice_bus := AudioServer.get_bus_index(&"Voice")
	var voice_db := AudioServer.get_bus_volume_db(voice_bus)
	for context in [&"menu", &"encounter", &"boss", &"victory"]:
		manager.set_world_audio_state(1, false, 1)
		manager.set_music_context(context)
		await create_timer(.4).timeout
		var expected := -13.0 if context == &"menu" else -19.0
		expect(absf(manager.music.volume_db - expected) < 1.5, "Only menu music gets +6 dB: " + String(context))
		expect(manager.voice.volume_db == -6 and AudioServer.get_bus_volume_db(voice_bus) == voice_db, "Music gain preserves Voice: " + String(context))
	expect(manager.voice.playback_type == AudioServer.PLAYBACK_TYPE_STREAM and manager.music.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "Web streaming playback policy retained")
	# Stress the raised menu cue with real speech even though the normal menu
	# has no automatic narration. Capture after the existing Master limiter.
	manager.set_music_context(&"menu")
	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, record)
	record.set_recording_active(true)
	manager.say(&"narration.intro", 2)
	await create_timer(.4).timeout
	record.set_recording_active(false)
	var capture := record.get_recording()
	var peak := 0.0
	if capture != null:
		for index in range(0, capture.data.size(), 2): peak = maxf(peak, absf(capture.data.decode_s16(index) / 32768.0))
	expect(peak > .001 and peak <= .90, "Raised menu music and real speech retain native Master headroom")
	expect(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"World")) < -7 and AudioServer.get_bus_volume_db(voice_bus) == voice_db, "Menu music is ducked while Voice gain remains unchanged")
	print(JSON.stringify({"menu_speech_mix_peak": peak}))
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	reset()
	manager.set_music_context(&"intro")
	# Probe all sixteen protagonist recordings, balanced round-robin over four
	# accepted starts per event. Reset cooldown only for this isolated probe.
	var distribution := {}
	var recording_count := 0
	for event in manager.library.clips:
		if not String(event).begins_with("protagonist."): continue
		reset()
		manager._variants.erase(event)
		var clips: Array = manager.library.clips[event]
		expect(clips.size() == 2, "Two supplied variants: " + String(event))
		var starts: Array[String] = []
		var first_variant := -1
		for index in range(4):
			manager._bark_cooldown = 0
			expect(manager.say(event), "Protagonist accepted in idle fixture: " + String(event))
			starts.append(manager.voice.stream.resource_path)
			if first_variant < 0: first_variant = clips.find(manager.voice.stream)
			expect(manager.voice.stream == clips[(first_variant + index) % 2], "Alternating variants from a varied first choice: " + String(event))
			if index < 2:
				await create_timer(.12).timeout
				expect(manager.voice.get_playback_position() > 0, "Actual protagonist variant advances: " + String(event))
				recording_count += 1
			manager.stop_dialogue()
		var count_before: int = manager._variants[event]
		expect(not manager.say(event) and manager._variants[event] == count_before, "Cooldown rejection does not consume variant: " + String(event))
		distribution[event] = starts
		var expected_next: int = manager._variants[event] % clips.size()
		manager._variants.clear()
		manager._load_voice_history()
		expect(manager._variants[event] == expected_next, "Next alternative survives a preferences reload: " + String(event))
	expect(recording_count == 16 and distribution.size() == 8, "Every protagonist recording exercised")
	reset()
	manager.say(&"protagonist.repair_started")
	manager.stop_dialogue()
	manager._process(149.9)
	expect(not manager.say(&"protagonist.under_pressure"), "Shared cooldown suppresses chatter for 150 seconds")
	manager._process(.2)
	expect(manager.say(&"protagonist.under_pressure"), "Barks available after shared cooldown")
	manager.stop_dialogue()
	expect(not manager.say(&"protagonist.boss_defeated", 2), "Protagonist milestones respect the same 150-second limit")
	manager.begin_run()
	expect(manager._bark_cooldown > 149, "Restarting cannot shorten the existing protagonist cooldown")
	reset()
	manager.say(&"tutorial.time_meter", 3)
	expect(not manager.say(&"protagonist.multi_kill"), "Teaching suppresses incidental reactions")
	expect(not manager.say(&"protagonist.boss_defeated", 2) and manager._queue.is_empty(), "Protagonist milestones cannot queue chatter behind teaching")
	manager.stop_dialogue()
	manager._process(19.9)
	expect(not manager.say(&"protagonist.under_pressure"), "Skipping instruction speech also preserves 20 seconds of quiet")
	manager._process(.2)
	expect(manager.say(&"protagonist.under_pressure"), "Chatter becomes eligible after the tutorial grace period")
	reset()
	# Real campaign signal wiring, using controlled events rather than claiming a
	# complete combat playthrough. No gameplay/UI source is changed by this check.
	var scenes := root.get_node("SceneManager")
	var saved_params: Dictionary = scenes.params.duplicate(true)
	scenes.params = {"skip_tutorials": true, "difficulty": &"easy"}
	var arena: Node3D = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena); current_scene = arena
	await process_frame; await physics_frame
	arena.set_physics_process(false)
	arena.set_process(false)
	# Campaign intentionally suppresses incidental speech during acquire/demo/
	# practice/exit; probe the same real signal wiring in its pressure phase.
	arena.mode = &"pressure"
	state.start_game()
	reset()
	manager.reactions.elapsed = ProtagonistVoice.EARLY_REPAIR_RESERVATION
	arena.player.wounded.emit(1.0)
	manager.step_reactions(0, true, false, false)
	expect(manager.current_event == &"protagonist.under_pressure", "Wounded signal is wired")
	reset()
	var popup := Control.new(); root.add_child(popup)
	scenes.popup_opened.emit(&"Repair", popup)
	manager.step_reactions(0, true, true, false)
	expect(manager.current_event == &"protagonist.repair_started", "Repair popup signal is wired")
	popup.queue_free()
	reset()
	arena.equipment.restore_tool(&"beam")
	arena.equipment.repaired.emit(&"beam", 1.0)
	manager.step_reactions(0, true, false, false)
	expect(manager.current_event == &"protagonist.repair_completed", "Full repair signal is wired")
	reset()
	manager.reactions.elapsed = ProtagonistVoice.EARLY_REPAIR_RESERVATION
	arena.weapons.combat_event.emit(&"cable_cut", Vector3.ZERO, 1.0)
	manager.step_reactions(0, true, false, false)
	expect(manager.current_event == &"protagonist.enemy_exposed", "Protection-cut signal is wired")
	reset(); arena._recent_kills.clear()
	manager.reactions.elapsed = ProtagonistVoice.EARLY_REPAIR_RESERVATION
	for index in range(3): arena.director.enemy_event.emit(&"target", &"death", Vector3.ZERO, 1.0)
	manager.step_reactions(0, true, false, false)
	expect(manager.current_event == &"protagonist.multi_kill", "Three death signals within kill window are wired")
	reset()
	arena.director.enemy_event.emit(&"loop_boss", &"death", Vector3.ZERO, 1.0)
	manager.step_reactions(0, true, false, false)
	expect(manager.current_event == &"protagonist.boss_defeated", "Boss death signal is wired")
	reset()
	arena.emergency_rewind.ended.emit()
	await process_frame; await process_frame
	manager.step_reactions(0, true, false, false)
	expect(manager.current_event == &"protagonist.rewind_recovered", "Deferred recovery signal is wired")
	reset()
	arena.wave_index = arena.waves.size() - 1
	arena._begin_wave()
	arena._process(0)
	expect(arena.mode == &"exit" and manager.current_event == &"protagonist.room_cleared", "Actual end-of-room handoff requests room-clear event")
	reset()
	state.open_menu()
	arena.player.wounded.emit(1.0)
	expect(manager.current_event == &"", "Non-playing state suppresses protagonist chatter")
	manager.set_music_context(&"intro")
	arena.feedback.reset_state(); arena.queue_free()
	await process_frame; await create_timer(.3).timeout
	scenes.params = saved_params
	for key in ["sound", "volume", "voice_volume"]: state.set_setting(key, saved[key])
	manager.speech_finished.disconnect(terminal)
	print(JSON.stringify({"protagonist_variants": distribution, "recordings_probed": recording_count, "wired_protagonist_events": 8}))
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
