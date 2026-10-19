extends SceneTree
## Exercise authored sliders, persisted settings and the real effect-player routes.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func bus_level(name: StringName) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(name))

func run() -> void:
	var state := root.get_node("GameState")
	var audio := root.get_node("AudioManager")
	var scenes := root.get_node("SceneManager")
	var saved: Dictionary = state.preferences()
	var config := ConfigFile.new()
	config.load(state.SETTINGS_PATH)
	for key in ["voice_volume", "music_volume", "effects_volume"]:
		if config.has_section_key("settings", key):
			config.erase_section_key("settings", key)
	config.save(state.SETTINGS_PATH)
	state.reload_preferences()
	var prefs: Dictionary = state.preferences()
	expect(is_equal_approx(prefs.volume, saved.volume), "Master setting survives adding mix controls")
	expect(is_equal_approx(prefs.voice_volume, .45), "Missing voice setting uses quieter default")
	expect(prefs.music_volume == 1.0 and prefs.effects_volume == 1.0, "Older saves get independent music/effect defaults")
	state.set_setting("sound", true)
	state.set_setting("fullscreen", false)
	var menu: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	var panel: Node = scenes.push_popup(&"Settings")
	panel.volume.value = 37
	panel.music_volume.value = 61
	panel.voice_volume.value = 24
	panel.effects_volume.value = 43
	prefs = state.preferences()
	for pair in [["volume", .37], ["music_volume", .61], ["voice_volume", .24], ["effects_volume", .43]]:
		expect(is_equal_approx(prefs[pair[0]], pair[1]), "Slider saves " + pair[0])
	expect(panel.get_node("%VoiceVolumeLabel").text == "Voice - 24%", "Labels show actual slider value")
	expect(absf(bus_level(&"Master") - linear_to_db(.37)) < .01, "Master has no hidden Web attenuation")
	expect(absf(bus_level(&"Music") - (linear_to_db(.61) + 6)) < .01, "Music has independent gain and boost")
	expect(absf(bus_level(&"Voice") - linear_to_db(.24)) < .01, "Voice has independent gain")
	expect(absf(bus_level(&"Effects") - linear_to_db(.43)) < .01 and absf(bus_level(&"Responsive") - linear_to_db(.43)) < .01, "Effects covers world and responsive cues")
	var music_before := bus_level(&"Music")
	state.set_setting("effects_volume", 0)
	expect(bus_level(&"Effects") <= -79 and bus_level(&"Responsive") <= -79, "Effect zero silences both routes")
	expect(is_equal_approx(bus_level(&"Music"), music_before) and absf(bus_level(&"Voice") - linear_to_db(.24)) < .01, "Effect mute leaves music and speech unchanged")
	state.reload_preferences()
	expect(is_equal_approx(state.preferences().music_volume, .61) and is_equal_approx(state.preferences().voice_volume, .24) and state.preferences().effects_volume == 0, "Reload preserves all saved mix settings")
	scenes.close_popup(&"Settings")
	panel = scenes.push_popup(&"Settings")
	expect(panel.music_volume.value == 61 and panel.voice_volume.value == 24 and panel.effects_volume.value == 0, "Reopened panel reflects persisted mix")
	scenes.close_popup(&"Settings")
	var feedback := CombatFeedback.new()
	root.add_child(feedback)
	expect(feedback._loops[&"ring_loop"].player.bus == &"Effects", "World loops use Effects")
	expect(feedback._loops[&"clock_loop"].player.bus == &"Time", "Clock keeps responsive time route")
	expect(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Effects")) == &"World", "World effects retain speech ducking")
	expect(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Music")) == &"World", "Music retains speech ducking")
	feedback.queue_free()
	for key in saved:
		state.set_setting(key, saved[key])
	audio.stop_dialogue()
	audio.set_music_context(&"intro")
	await create_timer(.25, true).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
