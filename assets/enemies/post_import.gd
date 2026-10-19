@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		for clip in ["Idle", "Walk"]:
			if node.has_animation(clip):
				node.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in range(node.mesh.get_surface_count()):
			var mat := node.mesh.surface_get_material(surface) as StandardMaterial3D
			if mat and mat.resource_name in ["Yellow", "Blue", "Orange"]:
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return scene
