extends SceneTree
# Content and routing/lifecycle checks. Dummy playback is NOT a listening test;
# the offline PCM audition reel is the deliverable for human review.
const Feedback = preload("res://scenes/prototype/combat_feedback.gd")
const KINDS: Array[StringName] = [&"target", &"swarmer", &"brute", &"skirmisher", &"warden", &"ranged", &"blue", &"yellow", &"orange", &"side_guard", &"front_guard", &"loop", &"zigzag", &"pair", &"loop_boss", &"sequence_boss", &"final_boss"]
var checks := 0
var failures: Array[String] = []
var feedback: CombatFeedback

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func pending(kind: StringName) -> Dictionary:
	for voice in feedback._voices:
		if voice.pending and voice.cue == kind: return voice
	return {}

func fresh() -> void:
	feedback.reset_state()
	feedback.muted = false
	feedback.music_enabled = false

func run() -> void:
	var listener := AudioListener3D.new()
	root.add_child(listener)
	listener.position = Vector3(0, 12, 8)
	listener.make_current()
	feedback = Feedback.new()
	root.add_child(feedback)
	feedback.muted = false
	var library := feedback.cue_library
	var immutable := {}
	for entry in library.cues:
		immutable[entry.id] = [entry.stream, entry.pitch, entry.volume_db, entry.priority, entry.responsive]
	expect(feedback.samples.size() == 94 and feedback._cues.size() == 94, "94 inspector cues load without startup synthesis")
	var native_players := 0
	for child in feedback.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D: native_players += 1
	expect(native_players == Feedback.MAX_VOICES and native_players == 16, "native players are bounded including every loop and music")
	for event: StringName in [&"warning", &"attack", &"hurt", &"death"]:
		var signatures := {}
		for kind in KINDS:
			var entry: CombatAudioCue = feedback._cues[StringName("enemy_%s_%s" % [kind, event])]
			signatures[[entry.stream.resource_path, entry.pitch]] = true
		expect(signatures.size() == KINDS.size(), "every archetype has a distinct %s stream/pitch identity" % event)
	expect(feedback.samples[&"flash_fire"] != feedback.samples[&"flash_charged"] and feedback.samples[&"pierce_hit"] != feedback.samples[&"flash_charged"], "quick shot, charged launch and piercing contact have separate content")
	expect(feedback.samples[&"ring_return"] != feedback.samples[&"hit"] and feedback.samples[&"cable_cut"] != feedback.samples[&"hit"], "cutter contact, cut and return remain distinct")
	expect(feedback.samples[&"repair_step"] != feedback.samples[&"repair_full"], "stage restoration and full repair have distinct confirmation")
	expect(feedback.samples[&"scrub_older"] != feedback.samples[&"scrub_newer"], "scrub directions have distinct spectral content")
	for bus: StringName in [&"World", &"Responsive", &"Time", &"Music"]:
		expect(AudioServer.get_bus_index(bus) >= 0, "native %s bus exists" % bus)
	var world_bus := AudioServer.get_bus_index(&"World")
	expect(AudioServer.get_bus_effect_count(world_bus) == 0, "world bus does not apply a second pitch slowdown")
	expect(AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter, "master has a native peak ceiling")
	expect(library.music is AudioStreamOggVorbis and library.music.get_length() > 359 and library.music.get_length() < 361, "one six-minute compressed music track is loaded")
	expect(library.music.loop and library.music.loop_offset == 0, "music has native bounded loop metadata")

	fresh()
	feedback.cue(&"flash_fire", Vector3(2, 1, -6), .4)
	expect(not pending(&"flash_fire").is_empty() and pending(&"flash_fire").player.volume_db > -40, "quick fire starts audible without waiting for the next feedback tick")
	feedback.cue(&"flash_pierce", Vector3(2, 1, -6))
	expect(pending(&"flash_fire").is_empty() and not pending(&"flash_charged").is_empty(), "piercing launch flag upgrades the pending shot without playing two bangs")
	expect(feedback._effects.size() == 1, "upgrading audio preserves the existing single launch visual")
	var voice: Dictionary = pending(&"flash_charged")
	expect(voice.player is AudioStreamPlayer3D and voice.player.global_position == Vector3(2, 1, -6), "world cues use native positioned players")
	expect(voice.player.bus == &"World" and voice.player.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE and voice.player.max_distance == 64, "world cues have distance falloff and finite range")

	fresh()
	feedback.enemy_cue(&"ranged", &"warning", Vector3(0, 1, -4))
	feedback.enemy_cue(&"ranged", &"warning", Vector3(1, 1, -4))
	expect(feedback.accepted_cues == 1 and feedback.dropped_cues == 1, "same-archetype warnings coalesce rather than barking per enemy per frame")
	feedback.enemy_cue(&"no_such_enemy", &"warning", Vector3.ZERO)
	expect(feedback.accepted_cues == 1, "unknown archetype does not create an arbitrary fallback bark")

	fresh()
	feedback.step(.02, .0036, .18, false, 0, null, null)
	var first: float = feedback.world_pitch
	expect(first > pow(.18, .45) and first < 1, "shared world pitch ramps into slow")
	for i in range(40): feedback.step(.02, .0036, .18, false, 0, null, null)
	feedback.enemy_cue(&"brute", &"attack", Vector3.ZERO)
	voice = pending(&"enemy_brute_attack")
	expect(is_equal_approx(voice.player.pitch_scale / float(voice.base_pitch), feedback.world_pitch), "monster uses exactly the same once-applied time policy as weapons")
	feedback.cue(&"repair_step", Vector3.ZERO)
	voice = pending(&"repair_step")
	expect(voice.player.pitch_scale == 1 and voice.player.bus == &"Responsive" and voice.player.panning_strength == 0, "repair confirmation stays readable and unspatialized in slow time")
	feedback.step(.10, 0, 0, true, 0, null, null)
	expect(pending(&"enemy_brute_attack").is_empty(), "entering frozen history permanently cancels queued monster sound")
	var count := feedback.accepted_cues
	feedback.enemy_cue(&"brute", &"death", Vector3.ZERO)
	feedback.cue(&"cable_cut", Vector3.ZERO)
	expect(feedback.accepted_cues == count, "historical monster deaths and cuts cannot emit while frozen")
	feedback.cue(&"recovery_confirm", Vector3.ZERO)
	expect(not pending(&"recovery_confirm").is_empty() and pending(&"recovery_confirm").player.pitch_scale == 1, "recovery confirmation bypasses the frozen world at normal pitch")
	feedback.step(.1, 0, 0, true, 2, null, null)
	expect(feedback._loops[&"scrub_older"].target > 0 and feedback._loops[&"scrub_newer"].target == 0, "older selection drives only the older movement layer")
	var speed_target := feedback.clock_pitch_target
	feedback.step(.1, 0, 0, true, 5, null, null)
	expect(feedback.clock_pitch_target > speed_target and feedback.clock_pitch < feedback.clock_pitch_target, "scrub speed audibly slews rather than jumping")
	feedback.step(.1, 0, 0, true, -2, null, null)
	expect(feedback._loops[&"scrub_newer"].target > 0 and feedback._loops[&"scrub_older"].target == 0, "newer selection switches to the distinct forward layer")
	feedback.step(.1, 0, 0, true, 0, null, null)
	expect(feedback._loops[&"scrub_older"].target == 0 and feedback._loops[&"scrub_newer"].target == 0 and feedback._loops[&"clock_loop"].target > 0, "stopped scrub silences movement but keeps time motor readable")
	feedback.step(.1, .1, 1, false, 0, null, null)
	expect(pending(&"enemy_brute_attack").is_empty(), "leaving history never requeues a cancelled monster event")

	fresh()
	feedback.set_music_playing(true)
	for i in range(20): feedback.step(.1, .1, 1, false, 0, null, null)
	var music_gain: float = feedback._music_gain
	for kind in KINDS: feedback.enemy_cue(kind, &"hurt", Vector3.ZERO)
	var low_count := 0
	for v in feedback._voices:
		if v.pending: low_count += 1
	expect(low_count == feedback._voices.size() - Feedback.RESERVED_IMPORTANT, "ordinary chatter leaves two voice slots for important cues")
	feedback.cue(&"player_hurt", Vector3.ZERO)
	feedback.cue(&"recovery_confirm", Vector3.ZERO)
	expect(not pending(&"player_hurt").is_empty() and not pending(&"recovery_confirm").is_empty(), "damage and confirmation remain audible under a saturated enemy chorus")
	feedback.enemy_cue(&"yellow", &"warning", Vector3.ZERO)
	expect(not pending(&"enemy_yellow_warning").is_empty(), "important warning can replace an unheard low-priority command")
	feedback.step(.02, .02, 1, false, 0, null, null)
	expect(feedback._music_gain < music_gain, "important foreground cues duck the music bed")
	expect(feedback.metrics().voices <= Feedback.MAX_VOICES, "priority admission preserves total voice cap")
	feedback.step(.2, .036, .18, false, 0, null, null)
	expect(is_equal_approx(feedback._music.pitch_scale, feedback.world_pitch), "music shares the once-applied world pitch policy")
	feedback.step(.2, 0, 0, true, 0, null, null)
	var frozen_music: float = feedback._music_gain
	feedback.step(.2, 0, 0, true, 0, null, null)
	expect(feedback._music_gain < frozen_music, "frozen combat fades its ambience without affecting the time motor")

	# Persisted mute and lifecycle checks use real native playback, not audibility.
	var config_path: String = Feedback.SETTINGS_PATH
	var had_config := FileAccess.file_exists(config_path)
	var saved := FileAccess.get_file_as_bytes(config_path) if had_config else PackedByteArray()
	feedback.toggle_mute()
	var all_silent := feedback._music.volume_db == -80
	for loop in feedback._loops.values(): all_silent = all_silent and loop.player.volume_db == -80
	for v in feedback._voices: all_silent = all_silent and v.player.volume_db == -80 and not v.pending
	expect(all_silent, "mute immediately silences music, motors, responsive and world voices")
	feedback.toggle_mute()
	fresh()
	feedback.step(.1, .018, .18, false, 0, null, null)
	feedback.cue(&"ui_click", Vector3.ZERO)
	await create_timer(.12).timeout
	expect(feedback._loops[&"clock_loop"].player.playing, "native time motor starts through the deferred flush")
	feedback.enemy_cue(&"final_boss", &"death", Vector3.ZERO)
	feedback.cue(&"repair_full", Vector3.ZERO)
	var world_voice: Dictionary = pending(&"enemy_final_boss_death")
	var responsive_voice: Dictionary = pending(&"repair_full")
	# 3D players start on a native physics update, not the deferred render frame.
	await create_timer(.08).timeout
	expect(world_voice.player.playing and responsive_voice.player.playing, "native world and responsive streams start before the pause probe")
	paused = true
	await create_timer(.03, true).timeout
	expect(world_voice.player.stream_paused and feedback._music.process_mode == Node.PROCESS_MODE_PAUSABLE, "native pause suspends world audio without an independent feedback clock")
	expect(not responsive_voice.player.stream_paused and feedback._loops[&"clock_loop"].player.process_mode == Node.PROCESS_MODE_ALWAYS, "native pause preserves repair confirmation and time motor")
	paused = false
	await process_frame
	for entry in library.cues:
		expect(immutable[entry.id] == [entry.stream, entry.pitch, entry.volume_db, entry.priority, entry.responsive], "shared cue resource stays immutable: " + String(entry.id))
	feedback.queue_free()
	listener.queue_free()
	await process_frame
	await create_timer(.1).timeout
	expect(not is_instance_valid(feedback), "active playback can leave the scene cleanly")
	if had_config:
		var file := FileAccess.open(config_path, FileAccess.WRITE)
		file.store_buffer(saved)
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
