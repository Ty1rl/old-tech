extends SceneTree
const UI=preload("res://scenes/ui/ui_style.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
func run()->void:
	create_timer(3,true).timeout.connect(func():push_error("UI scale lifecycle watchdog");quit(1))
	var view:=Control.new()
	expect(UI.scale_for(view)==1,"Detached UI has safe font scale before attaching")
	root.add_child(view);await process_frame
	expect(UI.scale_for(view)>=1 and UI.scale_for(view)<=1.5,"Attached UI retains bounded shared scale")
	root.remove_child(view)
	expect(UI.scale_for(view)==1,"Formerly ready UI can finish delayed presentation after scene removal")
	view.free()
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
