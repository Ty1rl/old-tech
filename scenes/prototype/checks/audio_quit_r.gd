extends SceneTree
## Exercise the same close-request path as the desktop window with real MP3s.
const Feedback = preload("res://scenes/prototype/combat_feedback.gd")
var terminals: Array = []
func _initialize() -> void: call_deferred("run")
func terminal(event: StringName, interrupted: bool) -> void:
	terminals.append([event, interrupted])
func run() -> void:
	var manager := root.get_node("AudioManager")
	var state := root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	for pair in [["sound", true], ["volume", .8], ["voice_volume", .9]]: state.set_setting(pair[0], pair[1])
	manager.speech_finished.connect(terminal)
	var feedback := Feedback.new()
	root.add_child(feedback)
	feedback.muted = false
	feedback.cue(&"recovery_confirm", Vector3.ZERO)
	feedback.step(.1, .1, 1, false, 0, null, null)
	feedback._set_loop(&"scrub_older", .5, 1, .2)
	manager.lesson(&"shot")
	manager.set_music_context(&"boss")
	await create_timer(.25).timeout
	var started: bool = manager.voice.playing and manager.music.playing
	root.close_requested.emit()
	var failures: Array[String] = []
	if not started: failures.append("Real voice/music did not start before close")
	if terminals.size() != 2 or not terminals.all(func(item): return item[1]): failures.append("Quit must cancel both accepted lesson events")
	if manager.instruction_busy() or manager.music.playing or manager.voice.playing: failures.append("Quit left active speech/music")
	if manager.say(&"tutorial.shot", 3) or manager.set_music_context(&"menu"): failures.append("Shutdown accepted a new request")
	if feedback.metrics().voices != 0: failures.append("Quit did not drain world audio admissions")
	for loop in feedback._loops.values():
		if loop.player.playing: failures.append("Quit left a native world loop playing")
	# Preferences are restored before the manager's bounded mixer drain/normal quit.
	for key in ["sound", "volume", "voice_volume"]: state.set_setting(key, saved[key])
	manager.speech_finished.disconnect(terminal)
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":6, "failures":failures}))
