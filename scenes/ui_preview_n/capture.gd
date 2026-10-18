extends SceneTree
## Isolated display fixture: real museum + player assets, actual TimeCore and
## equipment. No claim of a migrated arena/full run; jam-1 owns integration.
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-7/exports/round-n-wave2"
class DisplayPlayer extends Node3D:
	var camera: Camera3D
class DisplayWeapon extends Node3D:
	var selected_tool := 1
	var available_tools: Array[int] = [1, 2, 3]
	var charge := 0.0
	func presentation_state() -> Dictionary: return {"charging": charge > 0, "charge": charge}
var pictures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func settle(count: int = 8) -> void:
	for i in range(count): await process_frame
func snap(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/" + name + ".png") == OK)
	pictures.append(name); print("Saved ", name)
func run() -> void:
	create_timer(45, true).timeout.connect(func(): push_error("UI N preview watchdog"); quit(1))
	var scenes = root.get_node("SceneManager")
	var state = root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	state.set_setting("fullscreen", false)
	var main = load("res://scenes/main.tscn").instantiate(); root.add_child(main); current_scene = main; state.open_menu()
	await snap("01-menu")
	scenes.push_popup(&"Settings"); await snap("02-settings")
	scenes.close_popup(&"Settings"); await settle()
	root.size = Vector2i(640,360); await snap("03-menu-small")
	var settings = scenes.push_popup(&"Settings"); await settle()
	settings.get_node("%BackButton").grab_focus(); await snap("04-settings-small")
	scenes.close_popup(&"Settings"); await settle()
	scenes.push_popup(&"Developer"); await snap("05-encounters-small")
	scenes.close_popup(&"Developer"); await settle()
	root.size = Vector2i(1280,800)
	main.queue_free(); current_scene = null; await settle()
	state.start_game()
	var world := Node3D.new(); root.add_child(world)
	var museum = load("res://scenes/prototype/museum_environment.gd").new(); world.add_child(museum); museum.build(false)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color("211e1b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7a483"); environment.environment.ambient_light_energy = .7
	world.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-55,-30,0); light.light_energy = 1.2; light.shadow_enabled = true; world.add_child(light)
	var player := DisplayPlayer.new(); world.add_child(player)
	var visual = load("res://scenes/prototype/player_visual.gd").new(); player.add_child(visual)
	visual.position.y = 0; visual.scale = Vector3.ONE * .65
	player.camera = Camera3D.new(); world.add_child(player.camera)
	player.camera.position = Vector3(7,11,12); player.camera.fov = 48; player.camera.look_at(Vector3(0,.5,0)); player.camera.current = true
	var weapons := DisplayWeapon.new(); world.add_child(weapons)
	var equipment = load("res://scenes/prototype/equipment.gd").new()
	var layer := CanvasLayer.new(); root.add_child(layer)
	var hud = load("res://scenes/prototype/status_hud.gd").new(); layer.add_child(hud)
	var core = load("res://scenes/time/time_core.tscn").instantiate(); root.add_child(core)
	var controller: TimeController = core.get_node("TimeController"); controller.set_physics_process(false)
	var session: EmergencyRewind = core.get_node("EmergencyRewind")
	hud.bind_time_controller(controller); hud.readout_mode = 0
	equipment.spend(&"beam", equipment.capacity(&"beam") * .45)
	equipment.spend(&"cone", equipment.capacity(&"cone") * .25)
	controller.try_spend(35)
	hud.update_status(player, weapons, equipment); await snap("06-hud-three-tools")
	weapons.available_tools.assign([1]); hud.update_status(player, weapons, equipment); await snap("07-hud-one-tool")
	weapons.available_tools.assign([1,2,3]); weapons.selected_tool = 2; weapons.charge = .75
	visual.set_tool_index(2); hud.update_status(player, weapons, equipment); Input.warp_mouse(Vector2(850,330)); await snap("08-hud-charge")
	weapons.charge = 0
	# Real baseline repair panel is only a display fixture; jam-3 owns its migration.
	equipment.begin_repair(&"beam")
	var repair = load("res://scenes/prototype/repair.tscn").instantiate()
	repair.setup({"equipment": equipment, "tool": &"beam", "available_tools": [1,2,3]})
	layer.add_child(repair)
	hud.update_status(player, weapons, equipment); await snap("09-repair-meter")
	root.size = Vector2i(640,360); await snap("09b-repair-small")
	root.size = Vector2i(1280,800); await settle()
	repair.queue_free(); equipment.end_repair(); await settle()
	var emergency = load("res://scenes/ui/emergency_view.tscn").instantiate(); layer.add_child(emergency); emergency.bind_emergency_rewind(session)
	session.history = ReplayHistory.from_settings(controller.settings)
	for i in range(100):
		session.history.record(.05, func() -> Dictionary: return {"position":Vector3.ZERO})
	session.capture_present = func() -> Dictionary: return {"position": Vector3.ZERO}
	controller.apply_hit(1000); session.select(45)
	hud.update_status(player, weapons, equipment); await snap("10-emergency-past")
	root.size = Vector2i(640,360); await snap("11-emergency-small")
	session.confirm(); root.size = Vector2i(1280,800); await settle()
	state.pause(); await snap("12-pause")
	scenes.push_popup(&"Settings"); await snap("13-paused-settings")
	scenes.clear_popups(); state.start_game(); scenes.show_run_result(false); await snap("14-retry")
	for setting in saved: state.set_setting(setting, saved[setting])
	print(JSON.stringify({"status":"passed", "pictures":pictures.size(), "failures":[]})); quit(0)
