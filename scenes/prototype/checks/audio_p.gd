extends SceneTree
# Real compressed playback needs mixer time on both sides of teardown. No errors
# are filtered; check.py captures Godot's complete output through process exit.
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
	for cycle in range(2):
		var feedback := Feedback.new()
		root.add_child(feedback)
		feedback.muted = false
		feedback.set_music_playing(true)
		feedback.step(.2, .2, 1, false, 0, null, null)
		await create_timer(.20).timeout
		expect(feedback._music.playing and feedback._music.get_playback_position() > 0, "compressed music starts and actually advances before lifecycle probe %d" % cycle)
		feedback.step(.2, .036, .18, false, 0, null, null)
		expect(is_equal_approx(feedback._music.pitch_scale, feedback.world_pitch), "compressed music uses shared world pitch once")
		feedback.set_music_playing(false)
		feedback.step(2, 2, 1, false, 0, null, null)
		# Give the asynchronous mixer time to release the stopped Ogg playback.
		await create_timer(.12).timeout
		expect(not feedback._music.playing, "music disable fades/stops without leaving a compressed player active")
		feedback.set_music_playing(true)
		feedback.step(.2, .2, 1, false, 0, null, null)
		await create_timer(.12).timeout
		expect(feedback._music.playing, "compressed slot can restart after cleanup")
		# Exit with native playback active, not just a pending deferred command.
		feedback.queue_free()
		await process_frame
		await create_timer(.15).timeout
		expect(not is_instance_valid(feedback), "scene teardown releases active compressed player")

	var feedback := Feedback.new()
	root.add_child(feedback)
	feedback.muted = false
	feedback.cue(&"room_complete", Vector3.ZERO)
	feedback.cue(&"room_open", Vector3.ZERO)
	var pending := 0
	for voice in feedback._voices:
		if voice.pending: pending += 1
	expect(pending == 1 and feedback.accepted_cues == 1, "authored room-complete and open alias do not double-trigger")
	feedback.clear_effects()
	feedback.step(0, 0, 0, true, 0, null, null)
	var count: int = feedback.accepted_cues
	feedback.cue(&"room_complete", Vector3.ZERO)
	feedback.enemy_cue(&"ranged", &"attack", Vector3.ZERO)
	expect(feedback.accepted_cues == count, "demo/snapshot freeze cannot replay room or attack audio")
	feedback.cue(&"ui_click", Vector3.ZERO)
	feedback.cue(&"ui_click", Vector3.ZERO)
	pending = 0
	for voice in feedback._voices:
		if voice.pending and voice.cue == &"ui_click":
			pending += 1
			expect(voice.player.pitch_scale == 1, "demo/UI click stays at normal speed during frozen world")
	expect(pending == 1, "duplicate UI click events coalesce into one responsive click")
	feedback.queue_free()
	await process_frame
	await create_timer(.15).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
