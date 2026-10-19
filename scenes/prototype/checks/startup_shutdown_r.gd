extends SceneTree
## Actual window-close/audio shutdown while a cold transition is incomplete.
## Runner exit 0 proves teardown completes; errors/timeouts fail externally.
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(value: bool, text: String) -> void:
	checks+=1
	if not value: failures.append(text)
func run() -> void:
	create_timer(15,true).timeout.connect(func(): print(JSON.stringify({"status":"failed","checks":checks,"failures":["shutdown watchdog"]}));quit(1))
	var scenes=root.get_node("SceneManager")
	scenes.fade_duration=.01
	var main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main);current_scene=main
	root.get_node("GameState").open_menu()
	expect(scenes.start_play(),"Cold shutdown start accepted")
	while scenes._loading_path.is_empty(): await process_frame
	expect(scenes.is_transitioning() and not scenes._loading_path.is_empty(),"Quit interrupts actual staged resource work")
	expect(current_scene==main,"Quit happens before campaign construction")
	root.close_requested.emit() # Same path as a native OS close request.
	expect(scenes._cancel_requested,"Window close cancels scene work before audio teardown")
	while scenes.is_transitioning(): await process_frame
	expect(current_scene==main,"Closing never constructs the cancelled campaign")
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	if not failures.is_empty(): quit(1)
	# AudioManager owns the final quit after its existing bounded audio drain.
