@tool
extends EditorScenePostImport

# glTF does not encode loop intent. The mechanism sample stays a one-shot.
func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for clip in ["Idle", "Walk"]:
			if player.has_animation(clip):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return scene
