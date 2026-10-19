extends SceneTree
var enabled_at_initialize:=false
func _initialize() -> void:
	# Autoloads are not yet in tree during SceneTree initialization. The real
	# manager's field initializer is checked directly before adding a spare node.
	var script=load("res://scripts/autoloads/scene_manager.gd")
	var spare=script.new()
	enabled_at_initialize=spare.developer_tools
	spare.free()
	call_deferred("run")
func run() -> void:
	var manager=root.get_node("SceneManager")
	var ok: bool=enabled_at_initialize and manager.developer_tools and not OS.has_feature("web")
	print(JSON.stringify({"status":"passed" if ok else "failed","checks":1,"failures":[] if ok else ["native flag unavailable before ready/first frame"]}));quit(0 if ok else 1)
