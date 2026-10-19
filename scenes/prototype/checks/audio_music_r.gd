extends SceneTree
const Feedback = preload("res://scenes/prototype/combat_feedback.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)
func run() -> void:
	var manager := root.get_node("AudioManager")
	var state := root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	for pair in [["sound", true], ["volume", .8], ["voice_volume", .9]]: state.set_setting(pair[0], pair[1])
	var feedback := Feedback.new()
	root.add_child(feedback)
	feedback.muted = false
	var listener := AudioListener3D.new()
	root.add_child(listener)
	listener.make_current()
	var tracks: Dictionary = manager.music_library.music_tracks
	expect(tracks.size() == 4, "Exactly four semantic music tracks")
	var paths: Array[String] = []
	for context in [&"menu", &"encounter", &"boss", &"victory"]:
		var stream: AudioStreamMP3 = tracks[context]
		expect(stream != null and stream.get_length() > 10, "Supplied track decodes: " + String(context))
		expect(stream.loop == (context != &"victory"), "Music loop metadata: " + String(context))
		paths.append(stream.resource_path)
	expect(paths.size() == 4 and paths.all(func(path): return paths.count(path) == 1), "Contexts use distinct imported sources")
	for context in [&"menu", &"intro", &"encounter", &"boss", &"victory", &"menu"]:
		expect(manager.set_music_context(context), "Context accepted: " + String(context))
		await create_timer(.18).timeout
		if context == &"intro":
			expect(not manager.music.playing and manager.music.stream == null, "Intro has no backing music")
		else:
			expect(manager.music.stream == tracks[context] and manager.music.playing and manager.music.get_playback_position() > 0, "Native stream replaced and advances: " + String(context))
			expect(manager.music.process_mode == (Node.PROCESS_MODE_ALWAYS if context in [&"menu", &"victory"] else Node.PROCESS_MODE_PAUSABLE), "Pause policy: " + String(context))
	expect(not manager.set_music_context(&"missing") and manager.music_context == &"menu", "Unknown context cannot replace current stream")
	manager.set_music_context(&"boss")
	await create_timer(.18).timeout
	for boss in range(3):
		var before: float = manager.music.get_playback_position()
		manager.set_music_context(&"boss")
		await create_timer(.08).timeout
		expect(manager.music.stream == tracks[&"boss"] and manager.music.get_playback_position() >= before, "Boss %d reuses supplied boss track without restarting" % (boss + 1))
	feedback.set_music_playing(true)
	expect(manager.music_context == &"boss", "Legacy arena hook cannot override explicit boss context")
	manager.set_music_context(&"menu")
	manager.set_music_context(&"encounter")
	manager.set_music_context(&"boss")
	manager.set_music_context(&"intro")
	await create_timer(.15).timeout
	expect(not manager.music.playing and manager.music.stream == null, "Coalesced deferred starts cannot revive replaced track")
	feedback.set_music_playing(true)
	feedback.step(.2, .2, 1, false, 0, null, null)
	await create_timer(.2).timeout
	expect(manager.music_context == &"encounter" and manager.music.playing, "Compatibility arena hook uses contextual encounter track")
	feedback.step(.2, .036, .18, false, 0, null, null)
	await process_frame; await process_frame
	expect(is_equal_approx(manager.music.pitch_scale, feedback.world_pitch) and feedback.world_pitch > feedback.world_pitch_target, "Music uses once-applied smoothed world pitch")
	expect(feedback.clock_pitch != feedback.world_pitch, "Time motor retains independent slew/pitch")
	var gain: float = manager._music_gain
	feedback.cue(&"core_break", Vector3.ZERO)
	feedback.step(.02, .02, 1, false, 0, null, null)
	await create_timer(.25).timeout
	expect(manager._foreground_gain == .35 and manager._music_gain < gain, "Important foreground effects duck contextual music")
	feedback.step(.2, 0, 0, true, 2, null, null)
	await create_timer(.5).timeout
	expect(manager._music_gain < .04 and feedback._loops[&"scrub_older"].player.playing, "Scrub fades music while responsive time motor survives")
	for voice in feedback._voices:
		if not voice.responsive: expect(voice.remaining == 0 and not voice.pending, "Freeze discards world transient admission")
	feedback.step(.2, .2, 1, false, 0, null, null)
	await create_timer(.3).timeout
	expect(manager._music_gain > .5, "World music returns after scrub")
	var before_pause_position: float = manager.music.get_playback_position()
	paused = true
	await create_timer(.15, true).timeout
	print(JSON.stringify({"pause_probe": {"tree_paused": paused, "music_paused": manager.music.stream_paused, "music_playing": manager.music.playing, "music_can_process": manager.music.can_process(), "before": before_pause_position, "after": manager.music.get_playback_position()}}))
	expect(not manager.music.can_process(), "Tree pause suspends combat music natively")
	var paused_position: float = manager.music.get_playback_position()
	await create_timer(.15, true).timeout
	expect(absf(manager.music.get_playback_position() - paused_position) < .03, "Combat music playback position holds under pause")
	expect(paused_position > 0 and absf(paused_position - before_pause_position) < .1, "Pausing preserves active combat music playback cursor")
	paused = false
	await create_timer(.15).timeout
	expect(manager.music.get_playback_position() > paused_position, "Combat music resumes its native playback cursor")
	paused = true
	manager.set_music_context(&"menu")
	await create_timer(.15, true).timeout
	expect(not manager.music.stream_paused and manager.music.playing, "Menu context plays under paused tree")
	paused = false
	manager.set_music_context(&"encounter")
	state.set_setting("sound", false)
	await create_timer(.15).timeout
	expect(not manager.music.playing, "Sound mute stops contextual player")
	state.set_setting("sound", true)
	await create_timer(.2).timeout
	expect(manager.music.playing, "Unmuting resumes selected context without another owner")
	feedback.toggle_mute()
	await create_timer(.12).timeout
	expect(not manager.music.playing, "Legacy feedback mute suppresses world music immediately")
	feedback.toggle_mute()
	await create_timer(.15).timeout
	expect(manager.music.playing, "Legacy unmute restores world music")
	# Exercise the native finished latch using the real victory stream's end.
	manager.set_music_context(&"victory")
	await create_timer(.15).timeout
	manager.music.play(tracks[&"victory"].get_length() - .08)
	await create_timer(.4).timeout
	expect(not manager.music.playing and manager._music_completed, "Victory completes once without automatic restart")
	manager.set_music_context(&"intro")
	manager.set_music_context(&"victory")
	await create_timer(.15).timeout
	expect(manager.music.playing, "A later context entry can replay victory")
	var native_effect_players := 0
	for child in feedback.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D: native_effect_players += 1
	expect(native_effect_players == 15 and feedback._voices.size() == 9, "Effects bounded at six loops plus nine transients")
	expect(manager.get_child_count() == 2 and manager.music.bus == &"Music", "One global music player and one original voice player; no generated bed")
	expect(feedback.metrics().voice_cap == 15, "Effect metrics match actual native player bound")
	var supplied := 0
	for cue: CombatAudioCue in feedback.cue_library.cues:
		expect(cue.volume_db <= -6 and cue.volume_db >= -26, "Cue gain budget: " + String(cue.id))
		if "/supplied/" in cue.stream.resource_path:
			supplied += 1
			expect(cue.stream is AudioStreamMP3 and cue.stream.get_length() > .05, "Supplied effect decodes: " + String(cue.id))
	expect(supplied >= 22, "Supplied effects retain their stream resources")
	# Capture actual native mix after the existing Master limiter. This measures
	# signal/headroom only; it does not assert perceived quality or loudness.
	feedback.reset_state()
	manager.set_music_context(&"encounter")
	var voice_bus := AudioServer.get_bus_index(&"Voice")
	var original_voice_db := AudioServer.get_bus_volume_db(voice_bus)
	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, record)
	record.set_recording_active(true)
	manager.lesson(&"shot")
	for kind in [&"flash_charged", &"core_break", &"repair_full", &"room_open", &"player_hurt", &"recovery_confirm", &"emergency_start"]:
		feedback.cue(kind, Vector3.ZERO, 1.5)
	feedback.step(.01, .01, .18, false, 0, null, null)
	for kind in Feedback.LOOP_KINDS: feedback._set_loop(kind, .8, feedback.world_pitch, .2)
	await create_timer(.4).timeout
	record.set_recording_active(false)
	var capture := record.get_recording()
	var peak := 0.0
	if capture != null:
		for index in range(0, capture.data.size(), 2): peak = maxf(peak, absf(capture.data.decode_s16(index) / 32768.0))
	expect(capture != null and capture.data.size() > 1000 and peak > .001 and peak <= .90, "Actual overlapping effects/music/voice capture respects Master ceiling")
	expect(AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter and AudioServer.get_bus_effect(0, 0).ceiling_db == -1, "Existing -1 dB Master limiter retained")
	expect(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"World")) < -7, "World effects/music receive speech ducking")
	expect(AudioServer.get_bus_volume_db(voice_bus) == original_voice_db and manager.voice.volume_db == -3, "Ducking leaves Voice bus/node gain unchanged")
	expect(feedback.metrics().voices <= 15, "Overlap admission respects effect voice cap")
	print(JSON.stringify({"native_mix_peak": peak, "supplied_effect_cues": supplied, "effect_player_cap": 15, "global_music_players": 1, "global_voice_players": 1}))
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	manager.stop_dialogue()
	manager.set_music_context(&"intro")
	feedback.reset_state()
	feedback.queue_free(); listener.queue_free()
	await process_frame; await create_timer(.3).timeout
	expect(not is_instance_valid(feedback), "Compressed effect teardown completes cleanly")
	for key in ["sound", "volume", "voice_volume"]: state.set_setting(key, saved[key])
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
