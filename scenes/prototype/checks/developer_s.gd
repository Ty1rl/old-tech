extends SceneTree
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures.append(text)
func run() -> void:
	var scenes=root.get_node("SceneManager")
	expect(not scenes.developer_tools,"Native tools are off on the first frame by default")
	expect(scenes.push_popup(&"Developer")==null,"Disabled tools cannot open a developer popup")
	expect(not scenes.developer_opt_in(PackedStringArray(),false),"No native opt-in stays off")
	expect(scenes.developer_opt_in(PackedStringArray(["--developer"]),false),"Native explicit user flag enables tools")
	expect(not scenes.developer_opt_in(PackedStringArray(["--developer"]),true),"Web rejects developer user flag")
	expect(not scenes.developer_opt_in(PackedStringArray(["--developer=true"]),false),"Only exact flag opts in")
	var output: Array=[]
	var err:=OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://scenes/loading_r/checks/developer_arg_s.gd","--","--developer"]),output,true)
	expect(err==0,"Fresh native process accepts actual --developer user argument: "+str(output))
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
