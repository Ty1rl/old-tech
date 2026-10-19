extends SceneTree
## Small Round T checkpoint: real imported streams in a mounted audio-only PCK.
var checks := 0
var failures: Array[String] = []
var terminals: Array = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)
func terminal(event: StringName, interrupted: bool) -> void:
	terminals.append([event, interrupted])
func run() -> void:
	var manager := root.get_node("AudioManager")
	var state := root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	for pair in [["sound", true], ["volume", .8], ["voice_volume", .9]]: state.set_setting(pair[0], pair[1])
	var original: DialogueLibrary = manager.library
	var texts := {
		&"tutorial.movement": "Mouse aims. WASD moves.",
		&"tutorial.tool_switch": "Press Tab, one, two, or three; to select tools.",
		&"tutorial.rewind": "When your reserve runs out, a rewind charge gives you another chance. Scroll down to choose an earlier moment. Press Enter to confirm."}
	var out := OS.get_environment("XDG_CACHE_HOME").get_base_dir().path_join("exports/round-t")
	DirAccess.make_dir_recursive_absolute(out)
	var pack_path := out.path_join("audio-imports.pck")
	var pack := PCKPacker.new()
	expect(pack.pck_start(pack_path) == OK, "Create focused export pack")
	for event in texts:
		expect(original.transcripts.get(event) == texts[event], "Exact supplied caption: " + String(event))
		var stream: AudioStreamMP3 = original.clips[event][0]
		expect(stream != null and stream.get_length() > 1 and not stream.loop, "Imported clip decodes: " + String(event))
		var config := ConfigFile.new()
		expect(config.load(stream.resource_path + ".import") == OK, "Import remap exists: " + String(event))
		var alias := "res://round_t_audio/" + String(event).get_extension() + ".mp3str"
		expect(pack.add_file(alias, config.get_value("remap", "path")) == OK, "Pack actual imported stream: " + String(event))
	expect(pack.flush() == OK, "Finish audio-only export pack")
	expect(ProjectSettings.load_resource_pack(pack_path), "Mount exported audio pack")
	var fixture := DialogueLibrary.new()
	for event in texts:
		var alias := "res://round_t_audio/" + String(event).get_extension() + ".mp3str"
		var exported := ResourceLoader.load(alias, "AudioStreamMP3", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamMP3
		expect(exported != null, "Export pack resource loads: " + String(event))
		if exported == null: continue
		expect(exported.data == original.clips[event][0].data and is_equal_approx(exported.get_length(), original.clips[event][0].get_length()), "Packed encoded data/duration retained: " + String(event))
		fixture.clips[event] = [exported]
	fixture.clips[&"tutorial.rewind_charges"] = original.clips[&"tutorial.rewind_charges"]
	manager.begin_run(); manager.library = fixture
	manager.speech_finished.connect(terminal)
	expect(manager.say(&"tutorial.movement", 3), "Movement request accepted")
	await create_timer(.35).timeout
	expect(manager.voice.get_playback_position() > .05 and manager.instruction_busy(), "Packed movement advances natively")
	await create_timer(fixture.clips[&"tutorial.movement"][0].get_length() + .3).timeout
	expect(terminals == [[&"tutorial.movement", false]] and not manager.instruction_busy(), "Natural movement completion releases speech gate once")
	terminals.clear()
	manager.say(&"tutorial.tool_switch", 3)
	manager.say(&"tutorial.rewind", 2)
	await create_timer(.35).timeout
	expect(manager.voice.get_playback_position() > .05 and manager.is_speaking(&"tutorial.rewind"), "Packed tool switch advances with rewind queued")
	manager.stop_dialogue()
	expect(terminals == [[&"tutorial.tool_switch", true], [&"tutorial.rewind", true]] and not manager.instruction_busy(), "Skip distinguishes cancelled active/queued speech")
	terminals.clear()
	manager.say(&"tutorial.rewind", 3)
	manager.say(&"tutorial.rewind_charges", 2)
	await create_timer(.35).timeout
	expect(manager.voice.get_playback_position() > .05, "New packed rewind recording advances")
	manager.voice.seek(manager.voice.stream.get_length() - .1)
	await create_timer(.4).timeout
	expect(terminals == [[&"tutorial.rewind", false]] and manager.is_speaking(&"tutorial.rewind_charges") and manager.instruction_busy(), "Native rewind completion hands off separate charge statement")
	manager.stop_dialogue()
	expect(terminals.size() == 2 and terminals[1] == [&"tutorial.rewind_charges", true], "Charge statement cancellation stays distinct")
	expect(manager.voice.playback_type == AudioServer.PLAYBACK_TYPE_STREAM and manager.music.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "Voice/Music keep Stream playback")
	expect(manager.voice.volume_db == -3, "Original Voice node gain retained")
	manager.library = original
	manager.begin_run(); terminals.clear()
	manager.say(&"tutorial.tool_switch", 3)
	manager.say(&"tutorial.movement", 2)
	await create_timer(.2).timeout
	root.close_requested.emit()
	expect(terminals == [[&"tutorial.tool_switch", true], [&"tutorial.movement", true]] and not manager.voice.playing and not manager.instruction_busy(), "Normal quit cancels both requests before mixer drain")
	manager.speech_finished.disconnect(terminal)
	for key in ["sound", "volume", "voice_volume"]: state.set_setting(key, saved[key])
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures, "audio_pack":pack_path}))
