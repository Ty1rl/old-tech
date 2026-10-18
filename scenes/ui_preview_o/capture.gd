extends SceneTree
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-7/exports/round-o"
class DisplayWeapons extends Node3D:
	var selected_tool := 1
	var available_tools: Array[int] = [1,2,3]
	func presentation_state() -> Dictionary: return {}
var phase := "before"
func _initialize() -> void: call_deferred("run")
func settle(count: int = 8) -> void:
	for i in range(count): await process_frame
func snap(name: String) -> void:
	await settle(); await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT+"/"+phase+"-"+name+".png") == OK)
	print("Saved ", phase, "-", name)
func run() -> void:
	create_timer(45,true).timeout.connect(func():push_error("Round O capture watchdog");quit(1))
	phase = FileAccess.get_file_as_string(OUT+"/phase.txt").strip_edges()
	var state = root.get_node("GameState"); var scenes = root.get_node("SceneManager")
	var saved: Dictionary = state.preferences(); state.set_setting("fullscreen",false)
	var main = load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main;state.open_menu()
	await snap("menu")
	if phase == "after":
		main.get_node("MainMenu/%PlayButton").pressed.emit();await snap("start-easy")
		var start = scenes.get_popup(&"NewGame")
		start.get_node("%Hard").button_pressed=true;start.get_node("%StartButton").grab_focus()
		await snap("start-hard")
		root.size=Vector2i(640,360);await snap("start-small")
		scenes.close_popup(&"NewGame");await settle()
	root.size=Vector2i(1280,800);main.queue_free();current_scene=null;await settle();state.start_game()
	var world = load("res://scenes/ui/menu_backdrop.gd").new();root.add_child(world)
	var player = load("res://scenes/prototype/combat_player.tscn").instantiate();world.add_child(player)
	player.camera.current=true
	var controller = load(OUT+"/capability_time.gd").new();controller.auto_advance=false;root.add_child(controller);player.time_controller=controller
	var weapons := DisplayWeapons.new();world.add_child(weapons)
	var equipment := WeaponEquipment.new()
	var layer := CanvasLayer.new();root.add_child(layer)
	var hud = load("res://scenes/prototype/status_hud.gd").new();layer.add_child(hud);hud.bind_time_controller(controller);hud.readout_mode=0
	controller.try_spend(35);controller.set_capabilities(false,false)
	hud.update_status(player,weapons,equipment);await snap("hud-locked")
	controller.set_capabilities(true,true);hud.update_status(player,weapons,equipment);await snap("hud-unlocked")
	if phase == "after":
		var panel = load("res://scenes/ui/repair_condition.tscn").instantiate();layer.add_child(panel)
		panel.position=Vector2(35,100);panel.size=Vector2(310,210)
		equipment.spend(&"ring",equipment.capacity(&"ring")*.65);panel.bind_equipment(equipment,&"ring");hud.update_status(player,weapons,equipment)
		await snap("repair-before")
		equipment.begin_repair(&"ring");equipment.complete_step(&"ring");hud.update_status(player,weapons,equipment);await snap("repair-checkpoint")
		panel.queue_free();equipment.end_repair()
	var session := EmergencyRewind.new();session.time_controller=controller;root.add_child(session)
	session.history=ReplayHistory.from_settings(controller.settings)
	for i in range(100):session.history.record(.05,func()->Dictionary:return {"position":Vector3.ZERO})
	var view=load("res://scenes/ui/emergency_view.tscn").instantiate();layer.add_child(view);view.bind_emergency_rewind(session)
	controller.force_depletion();session.select(45);await snap("recovery")
	root.size=Vector2i(640,360);await snap("recovery-small")
	for i in [0,99]:
		session.select(i);await snap("recovery-small-%d" % i)
	for setting in saved:state.set_setting(setting,saved[setting])
	print(JSON.stringify({"status":"passed","failures":[]}));quit(0)
