extends SceneTree
## Native speech lifetime probes, isolated from campaign/intro presentation.
var checks := 0
var failures: Array[String] = []
var terminals: Array[Dictionary] = []
var manager: Node

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)
func terminal(event: StringName, interrupted: bool) -> void:
	terminals.append({"event": event, "interrupted": interrupted, "busy": manager.instruction_busy()})
func fixture() -> DialogueLibrary:
	var result := DialogueLibrary.new()
	var short := AudioStreamWAV.new()
	short.format = AudioStreamWAV.FORMAT_16_BITS
	short.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(4410) # .1 seconds, native PCM; no production audio is generated.
	short.data = data
	for id in [&"tutorial.a", &"tutorial.b", &"tutorial.c", &"tutorial.d", &"tutorial.e", &"narration.intro", &"boss.test", &"bark"]:
		result.clips[id] = [short]
	result.clips[&"tutorial.empty"] = []
	result.clips[&"tutorial.invalid"] = [null, AudioStreamWAV.new()]
	result.clips[&"tutorial.malformed"] = null
	return result
func reset() -> void:
	manager.begin_run()
	terminals.clear()
func expect_cancelled(count: int, label: String) -> void:
	expect(terminals.size() == count, label + " emits exactly one terminal per accepted request")
	for item in terminals:
		expect(item.interrupted, label + " marks interruption")
	expect(not manager.instruction_busy() and not manager.is_speaking(&"tutorial.a"), label + " clears wait predicates")

func run() -> void:
	manager = root.get_node("AudioManager")
	var state := root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	for pair in [["sound", true], ["volume", .8], ["voice_volume", .9]]: state.set_setting(pair[0], pair[1])
	manager.speech_finished.connect(terminal)
	var recorded: DialogueLibrary = manager.library
	manager.library = fixture()
	expect(manager.current_event == &"" and manager.played_events.is_empty(), "Manager does not automatically narrate on startup")
	expect(not manager.is_speaking(&"") and not manager.instruction_busy(), "Idle and empty event are not speech")
	for id in [&"tutorial.missing", &"tutorial.empty", &"tutorial.invalid", &"tutorial.malformed"]:
		expect(not manager.say(id, 3) and not manager.instruction_busy(), "Missing/unplayable clip does not block: " + String(id))
	expect(terminals.is_empty(), "Rejected requests do not create terminal obligations")
	expect(manager.say(&"boss.test", 3), "Non-instruction speech accepted")
	expect(not manager.instruction_busy(), "Boss speech alone is not instruction busy")
	expect(manager.say(&"tutorial.a", 2), "Tutorial accepted behind other speech")
	expect(manager.instruction_busy() and manager.is_speaking(&"tutorial.a"), "Queued tutorial participates in both predicates")
	reset()
	expect(manager.say(&"tutorial.a", 3) and manager.say(&"tutorial.b", 2), "Two instructions accepted")
	expect(not manager.say(&"tutorial.a", 3), "Duplicate current request rejected")
	expect(not manager.say(&"tutorial.b", 2), "Duplicate queued request rejected")
	await create_timer(.7).timeout
	print(JSON.stringify({"native_speech_chain": terminals}))
	expect(terminals.size() == 2, "Native completion delivers two terminal events")
	if terminals.size() == 2:
		expect(terminals[0].event == &"tutorial.a" and not terminals[0].interrupted and terminals[0].busy, "First completion hands off queued instruction before notification")
		expect(terminals[1].event == &"tutorial.b" and not terminals[1].interrupted and not terminals[1].busy, "Last natural completion releases gate")
	expect(not manager.instruction_busy() and not manager.is_speaking(&"tutorial.b"), "Native completion leaves no busy state")
	reset()
	manager.say(&"tutorial.a", 3)
	for id in [&"tutorial.b", &"tutorial.c", &"tutorial.d"]: expect(manager.say(id, 2), "Bounded queue accepts " + String(id))
	expect(not manager.say(&"tutorial.e", 2), "Fourth queued request is rejected")
	manager.stop_dialogue()
	expect_cancelled(4, "Explicit stop")
	manager.stop_dialogue()
	expect(terminals.size() == 4, "Repeated stop emits no duplicate terminals")
	reset()
	manager.say(&"tutorial.a", 2)
	manager.say(&"tutorial.b", 2)
	expect(manager.say(&"boss.test", 3), "High priority preemption accepted")
	expect(terminals.size() == 2 and terminals.all(func(item): return item.interrupted), "Preemption cancels current and queued obligations")
	expect(not manager.instruction_busy() and manager.is_speaking(&"boss.test"), "Preemption exposes only new speech")
	reset()
	manager.say(&"tutorial.a", 3)
	manager.say(&"tutorial.b", 2)
	manager.begin_run()
	expect_cancelled(2, "Restart")
	reset()
	manager.say(&"tutorial.a", 3, true)
	manager.stop_dialogue()
	expect(not manager.say(&"tutorial.a", 3, true), "Once event stays consumed within run")
	manager.begin_run()
	expect(manager.say(&"tutorial.a", 3, true), "Restart re-enables once event")
	reset()
	expect(manager.play_intro() and not manager.play_intro(), "Explicit intro plays once per run")
	manager.begin_run()
	expect(manager.play_intro(), "New run can explicitly replay intro")
	reset()
	manager.lesson(&"a")
	expect(manager.instruction_busy() and manager.is_speaking(&"tutorial.a"), "Existing lesson API remains compatible")
	reset()
	manager.say(&"tutorial.a", 3)
	manager.say(&"tutorial.b", 2)
	paused = true
	await create_timer(.3, true).timeout
	expect(manager.instruction_busy() and terminals.is_empty() and manager.voice.stream_paused, "Pause suspends native voice without falsely completing tutorial")
	manager.stop_dialogue()
	expect_cancelled(2, "Skip during pause")
	paused = false
	reset()
	manager.say(&"tutorial.a", 3)
	manager.voice.stop()
	await create_timer(.4).timeout
	expect_cancelled(1, "Externally stopped playback watchdog")
	reset()
	manager.say(&"tutorial.a", 3)
	manager.say(&"tutorial.b", 2)
	state.set_setting("sound", false)
	expect(not manager.instruction_busy() and not manager.say(&"tutorial.c", 3), "Sound disabled immediately bypasses gate/rejects new requests")
	await process_frame; await process_frame
	expect_cancelled(2, "Sound disabled")
	state.set_setting("sound", true)
	reset()
	manager.say(&"tutorial.a", 3)
	manager.say(&"tutorial.b", 2)
	state.set_setting("voice_volume", 0)
	await process_frame; await process_frame
	expect_cancelled(2, "Voice zero volume")
	expect(not manager.say(&"tutorial.c", 3), "Inaudible Voice rejects blocking speech")
	state.set_setting("voice_volume", .9)
	reset()
	manager.say(&"tutorial.a", 3)
	state.set_setting("volume", 0)
	await process_frame; await process_frame
	expect_cancelled(1, "Master zero volume")
	state.set_setting("volume", .8)
	reset()
	manager.say(&"tutorial.a", 3)
	manager.library = null
	await process_frame; await process_frame
	expect_cancelled(1, "Missing library")
	expect(not manager.say(&"tutorial.a", 3), "Missing library rejects request")
	manager.library = fixture()
	reset()
	var scene := Node.new()
	root.add_child(scene); current_scene = scene
	await process_frame; await process_frame
	manager.say(&"tutorial.a", 3)
	manager.say(&"tutorial.b", 2)
	scene.queue_free()
	await process_frame; await process_frame
	expect_cancelled(2, "Real scene tree exit")
	reset()
	manager.say(&"tutorial.a", 3)
	manager.say(&"tutorial.b", 2)
	root.get_node("SceneManager").scene_changed.emit(&"MainMenu")
	expect_cancelled(2, "Scene-change notification")
	manager.library = recorded
	reset()
	var count := 0
	for event in recorded.clips:
		for clip: AudioStream in recorded.clips[event]:
			count += 1
			expect(clip is AudioStreamMP3 and clip.get_length() > .1, "Supplied speech decodes: " + String(event))
	expect(count == 40 and manager.voice.volume_db == -6 and manager.voice.bus == &"Voice", "All 40 current recordings and reduced Voice gain and original bus preserved")
	var voice_bus := AudioServer.get_bus_index(&"Voice")
	var effect := AudioEffectRecord.new()
	AudioServer.add_bus_effect(voice_bus, effect)
	effect.set_recording_active(true)
	manager.lesson(&"shot")
	await create_timer(.4).timeout
	effect.set_recording_active(false)
	var pcm := effect.get_recording()
	expect(manager.is_speaking(&"tutorial.shot") and not manager.is_speaking(&"tutorial.time_meter"), "Shot no longer automatically queues reserve explanation")
	expect(manager.voice.get_playback_position() > .1 and pcm != null and pcm.data.size() > 1000, "Actual supplied speech advances and produces native captured PCM")
	expect(not manager.say(&"protagonist.under_pressure"), "Incidental bark cannot interrupt teaching")
	manager.stop_dialogue()
	AudioServer.remove_bus_effect(voice_bus, AudioServer.get_bus_effect_count(voice_bus) - 1)
	await create_timer(.2).timeout
	for key in ["sound", "volume", "voice_volume"]: state.set_setting(key, saved[key])
	manager.speech_finished.disconnect(terminal)
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
