@tool
extends EditorScenePostImport

# glTF has no standard animation-loop flag. Preserve the exact clip names and
# mark their cycles explicitly on Godot import, without runtime gameplay code.
func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for clip in ["Idle", "Walk", "Run", "BackWalk", "RingHold", "FlashHold", "ConeHold", "ClockHold"]:
			if player.has_animation(clip):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return scene
