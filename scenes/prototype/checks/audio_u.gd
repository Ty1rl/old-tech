extends SceneTree
## Round U focused check: Web audio buffering/sample policy, stall resilience, and idle loop stop.

const Feedback = preload("res://scenes/prototype/combat_feedback.gd")

var checks := 0
var failures: Array[String] = []
var terminals: Array[Array] = []
var manager: Node


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func _on_terminal(event: StringName, interrupted: bool) -> void:
	terminals.append([event, interrupted])


func _reset() -> void:
	manager.begin_run()
	terminals.clear()


func run() -> void:
	manager = root.get_node("AudioManager")
	var state := root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	for pair in [["sound", true], ["volume", 0.8], ["voice_volume", 0.9]]:
		state.set_setting(pair[0], pair[1])
	manager.speech_finished.connect(_on_terminal)

	# 1. Project settings & playback type policy (native vs Web).
	var web_latency := int(ProjectSettings.get_setting("audio/driver/output_latency.web", 50))
	expect(web_latency >= 200 and web_latency <= 400, "Web output latency buffering configured in project.godot (%d ms)" % web_latency)
	expect(manager.voice.playback_type == AudioServer.PLAYBACK_TYPE_STREAM and manager.music.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "Native runtime keeps Stream playback for Voice and Music")

	manager.configure_playback_types(true)
	expect(manager.web_sample_voice and manager.voice.playback_type == AudioServer.PLAYBACK_TYPE_SAMPLE and manager.music.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "Web policy selects Sample for Voice while keeping Music on Stream to bound decoded memory")
	manager.configure_playback_types(false)
	expect(not manager.web_sample_voice and manager.voice.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "Restoring native policy returns Voice to Stream")

	# 2. Web Voice policy: stall resilience, natural completion, pause/resume, ducking, queue & scene cancellation.
	manager.web_sample_voice = true
	_reset()
	expect(manager.say(&"tutorial.movement", 3), "Movement tutorial accepted under Web voice policy")
	await create_timer(0.15).timeout
	# Simulate a 1.2s main-thread stall on Web; clamped elapsed tracking must not falsely abort the active clip.
	manager._process(1.2)
	expect(manager.instruction_busy() and terminals.is_empty(), "Simulated 1.2s Web frame stall does not prematurely cut off active tutorial voice")
	var world_bus := AudioServer.get_bus_index(&"World")
	expect(AudioServer.get_bus_volume_db(world_bus) < -6.0, "Active speech ducks World bus")

	paused = true
	await create_timer(0.15, true).timeout
	expect(manager.voice.stream_paused and manager.instruction_busy() and terminals.is_empty(), "Pause suspends voice without false tutorial completion")
	paused = false
	await create_timer(0.05).timeout
	expect(not manager.voice.stream_paused, "Unpause resumes voice cleanly")

	# Simulate Web Sample finishing at end of clip duration before native finished signal.
	var clip_len: float = manager.voice.stream.get_length()
	manager._speech_elapsed = clip_len
	manager.voice.stop()
	manager._process(0.016)
	await process_frame
	expect(terminals == [[&"tutorial.movement", false]] and not manager.instruction_busy(), "Web sample natural end-of-clip completion emits interrupted=false and releases gate")

	# Early external stop still reports interrupted=true.
	_reset()
	expect(manager.say(&"tutorial.tool_switch", 3) and manager.say(&"tutorial.rewind_charges", 2), "Queued tutorial chain accepted")
	await create_timer(0.25).timeout
	manager.voice.stop()
	manager._process(0.05)
	await process_frame
	expect(terminals.size() == 1 and terminals[0] == [&"tutorial.tool_switch", true] and manager.is_speaking(&"tutorial.rewind_charges"), "Early stop marks first clip interrupted and hands off queued tutorial.rewind_charges")
	root.get_node("SceneManager").scene_changed.emit(&"MainMenu")
	expect(terminals.size() == 2 and terminals[1] == [&"tutorial.rewind_charges", true] and not manager.instruction_busy(), "Scene change cancels remaining speech")

	# 3. Music contexts, slow-time pitch, pause guard, and frozen fade.
	manager.configure_playback_types(false)
	for ctx in [&"menu", &"encounter", &"boss", &"victory"]:
		manager.set_world_audio_state(1.0, false, 1.0, false)
		expect(manager.set_music_context(ctx), "Music context accepted: " + String(ctx))
		await create_timer(0.2).timeout
		expect(manager.music.playing and not manager.music.stream_paused, "Music context plays: " + String(ctx))
	manager.set_music_context(&"encounter")
	await create_timer(0.15).timeout
	manager.set_world_audio_state(0.45, false, 1.0, false)
	manager._process(0.1)
	expect(is_equal_approx(manager.music.pitch_scale, 0.45), "Encounter music follows slow-time world pitch")
	paused = true
	manager._process(0.05)
	expect(manager.music.stream_paused, "Encounter music pauses when tree pauses")
	manager._process(0.05)
	expect(manager.music.stream_paused and not manager._music_pending, "Paused music does not queue redundant restarts")
	paused = false
	manager._process(0.05)
	expect(not manager.music.stream_paused, "Encounter music resumes on unpause")
	manager.set_world_audio_state(0.45, true, 1.0, false)
	for _i in range(40):
		manager._process(0.05)
	expect(not manager.music.playing and manager._music_gain < 0.001, "Frozen combat fades and stops music player cleanly")
	manager.set_music_context(&"intro")

	# 4. CombatFeedback: active loops stop when gain decays to zero; expired voices stop player.
	var feedback := Feedback.new()
	root.add_child(feedback)
	var weapons := preload("res://scenes/weapons/weapons.tscn").instantiate()
	root.add_child(weapons)
	var orig_mute: bool = feedback.muted
	feedback.muted = false
	weapons.ring.flight_phase = "outbound"
	weapons.bellows.active = true
	feedback.step(0.1, 0.1, 0.25, false, 0.0, weapons, null)
	await create_timer(0.08).timeout
	expect(feedback._loops[&"ring_loop"].player.playing and feedback._loops[&"cone_loop"].player.playing and feedback._loops[&"clock_loop"].player.playing, "Active tool and slow-time loops start playing")
	weapons.ring.flight_phase = "idle"
	weapons.bellows.active = false
	for _i in range(90):
		feedback.step(0.05, 0.05, 1.0, false, 0.0, weapons, null)
	var all_stopped := true
	for kind in Feedback.LOOP_KINDS:
		var loop: Dictionary = feedback._loops[kind]
		all_stopped = all_stopped and not loop.player.playing and float(loop.gain) == 0.0 and is_equal_approx(loop.player.volume_db, -80.0)
	expect(all_stopped, "Silent loops stop playing and zero gain so Web Sample loops do not churn background restarts")

	feedback.cue(&"hit", Vector3.ZERO)
	await create_timer(0.05).timeout
	for _i in range(40):
		feedback.step(0.05, 0.05, 1.0, false, 0.0, weapons, null)
	var voices_stopped := true
	for v in feedback._voices:
		voices_stopped = voices_stopped and not v.player.playing and is_equal_approx(v.player.volume_db, -80.0)
	expect(voices_stopped, "Expired transient 3D voices stop their players cleanly")

	# Mixed archetypes share a quiet crowd budget without blocking player shots.
	feedback.reset_state()
	feedback.enemy_cue(&"blue", &"warning", Vector3.ZERO)
	for kind: StringName in [&"yellow", &"orange", &"swarmer", &"brute", &"ranged"]:
		feedback.enemy_cue(kind, &"warning", Vector3.ZERO)
	var monster_count := 0
	for voice in feedback._voices:
		if float(voice.remaining) > 0 and String(voice.cue).begins_with("enemy_"): monster_count += 1
	expect(monster_count == 1, "Mixed swarm burst produces one monster cue, not one per archetype")
	# Release cadence to exercise the separate overlapping-voice limit.
	feedback._cooldowns[&"monster_voice"] = 0.0
	feedback.enemy_cue(&"orange", &"death", Vector3.ZERO)
	feedback._cooldowns[&"monster_voice"] = 0.0
	feedback.enemy_cue(&"yellow", &"attack", Vector3.ZERO)
	monster_count = 0
	for voice in feedback._voices:
		if float(voice.remaining) > 0 and String(voice.cue).begins_with("enemy_"): monster_count += 1
	expect(monster_count == 2, "At most two monster sounds overlap even with cadence released")
	feedback.cue(&"flash_fire", Vector3.ZERO, .75)
	var shot_pending := false
	for voice in feedback._voices:
		if voice.cue == &"flash_fire" and voice.pending: shot_pending = true
	expect(shot_pending, "Monster crowd leaves room for the player's shot")
	feedback.reset_state()
	expect(not feedback._cooldowns.has(&"monster_voice"), "Restart clears monster cadence")

	feedback.muted = orig_mute
	feedback.free()
	weapons.free()
	await create_timer(0.05).timeout
	manager.speech_finished.disconnect(_on_terminal)
	for key in ["sound", "volume", "voice_volume"]:
		state.set_setting(key, saved[key])
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
