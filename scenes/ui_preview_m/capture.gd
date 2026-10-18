extends SceneTree
const OUT := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-7/exports/round-m"
class DisplayHistory extends RefCounted:
	var inspecting := true
	var available_seconds := 4.0
	var selected_seconds_ago := 1.2
var phase: String
func _initialize() -> void: call_deferred("run")
func settle(count: int = 5) -> void:
	for i in range(count): await process_frame
func snap(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT+"/"+phase+"-"+name+".png")==OK)
	print("Saved ",phase,"-",name)
func run() -> void:
	create_timer(35,true).timeout.connect(func():push_error("UI preview watchdog");quit(1))
	phase = FileAccess.get_file_as_string(OUT+"/phase.txt").strip_edges()
	var scenes = root.get_node("SceneManager")
	var state = root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	state.set_setting("tutorial",false); state.set_setting("hud",2); state.set_setting("fullscreen",false)
	var menu = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu); current_scene = menu; state.open_menu()
	await snap("menu")
	scenes.push_popup(&"Settings")
	await snap("settings")
	scenes.close_popup(&"Settings"); await settle()
	root.size = Vector2i(640,360)
	await snap("menu-small")
	scenes.push_popup(&"Settings")
	await snap("settings-small")
	scenes.close_popup(&"Settings"); await settle()
	scenes.push_popup(&"Developer")
	await snap("encounters-small")
	scenes.close_popup(&"Developer"); await settle()
	root.size = Vector2i(1280,800)
	scenes.push_popup(&"Developer")
	await snap("encounters")
	scenes.close_popup(&"Developer"); await settle()
	var arena = load("res://scenes/prototype/campaign.tscn").instantiate()
	current_scene = null; menu.queue_free(); await settle()
	scenes.params = {"debug_room":1,"debug_wave":2}
	root.add_child(arena); current_scene = arena
	arena.set_physics_process(false)
	arena.director.clear()
	arena.director.spawn(&"yellow",Vector3(-3,0,-5))
	arena.director.spawn(&"blue",Vector3(3,0,-5))
	await settle(30)
	arena.weapons.select_tool(2)
	arena.equipment.spend(&"beam",arena.equipment.capacity(&"beam")*.4)
	arena._update_hud()
	await snap("hud")
	arena.weapons.beam_charging = true; arena.weapons.beam_charge = .78
	arena._update_hud()
	Input.warp_mouse(Vector2(850,360))
	await snap("hud-charge")
	arena.weapons.beam_charging = false
	arena.status_hud.update_status(arena.player,arena.weapons,arena.equipment)
	arena.status_hud.update_timeline(DisplayHistory.new(),1.2,"",10.8)
	await snap("hud-rewind")
	arena._update_hud()
	state.pause()
	await snap("pause")
	scenes.push_popup(&"Settings")
	await snap("paused-settings")
	scenes.close_popup(&"Settings"); await settle(); state.resume()
	arena.weapons.available_tools.assign([2])
	arena._update_hud()
	root.size = Vector2i(640,360)
	await snap("hud-locked-small")
	for key in saved: state.set_setting(key,saved[key])
	print("UI M private capture finished"); quit(0)
