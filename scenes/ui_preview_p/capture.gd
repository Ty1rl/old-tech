extends SceneTree
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-7/exports/round-p-a"
var pictures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func settle(count: int = 10) -> void:
	for i in range(count): await process_frame
func snap(name: String) -> void:
	await settle(); await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT+"/"+name+".png")==OK)
	pictures.append(name);print("Saved ",name)
func shot(enemy: CombatPatternEnemy, point: Vector3, charge: float = 0) -> void:
	enemy.receive_attack(&"beam",30,point,{"segment_start":point-Vector3(0,0,.12),"segment_end":point+Vector3(0,0,.12),"radius":.01,"charge":charge})
func selected_bounds(repair: WeaponRepair) -> Rect2:
	var holder:Node3D=repair.model_instances[String(repair.tool)]
	var result:=Rect2()
	var first:=true
	for mesh:MeshInstance3D in holder.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree():continue
		var bounds:=mesh.get_aabb()
		for i in range(8):
			var point:=bounds.position+bounds.size*Vector3(i&1,(i>>1)&1,(i>>2)&1)
			var pixel:=repair.preview_cam.unproject_position(mesh.global_transform*point)
			var at:=repair.viewport_container.position+pixel/Vector2(repair.sub_viewport.size)*repair.viewport_container.size
			result=Rect2(at,Vector2.ZERO) if first else result.expand(at)
			first=false
	return result

func frame_model(repair:WeaponRepair,carousel:RepairCarouselView) -> void:
	repair.set_process(false)
	repair.viewport_container.modulate.a=1
	repair.viewport_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	repair.viewport_container.position=Vector2(280,200)
	repair.viewport_container.size=Vector2(720,360)
	await settle()
	var bounds:=selected_bounds(repair)
	repair.viewport_container.position+=root.get_visible_rect().size*Vector2(.5,.5)-bounds.get_center()
	await settle()
	carousel.set_model_region(selected_bounds(repair).grow(12))

func run() -> void:
	create_timer(45,true).timeout.connect(func():push_error("UI P visual watchdog");quit(1))
	var state=root.get_node("GameState");var saved:Dictionary=state.preferences();state.set_setting("fullscreen",false)
	var layer:=CanvasLayer.new();root.add_child(layer)
	var background:=ColorRect.new();background.color=Color("25251f");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(background)
	var gear:=WeaponEquipment.new()
	gear.spend(&"ring",gear.capacity(&"ring")*.65);gear.spend(&"beam",gear.capacity(&"beam")*.48);gear.spend(&"cone",gear.capacity(&"cone")*.85)
	# Disposable composition uses JAM-3's ACTUAL current repair scene, including
	# its central viewport and projected parts. No replacement central model.
	var repair:WeaponRepair=load("res://scenes/prototype/repair.tscn").instantiate()
	repair.setup({"equipment":gear,"tool":&"ring","available_tools":[1,2,3],"allow_full_preview":true})
	layer.add_child(repair)
	await settle()
	# Isolate the ACTUAL central viewport, without the unchanged legacy labels.
	# No selected model/camera/part transform is authored by this fixture.
	repair.viewport_container.reparent(layer)
	repair.hide()
	var carousel:RepairCarouselView=load("res://scenes/ui/repair_carousel.tscn").instantiate();layer.add_child(carousel)
	carousel.tool_selected.connect(func(tool:StringName):repair.switch_tool(tool);carousel.bind_equipment(gear,tool,[1,2,3]))
	for tool:StringName in WeaponEquipment.TOOLS:
		repair.preview_rect=Rect2(280,36,720,650);repair._update_layout();repair.switch_tool(tool)
		await settle(20)
		repair.set_process(false)
		repair.condition_view.hide()
		carousel.bind_equipment(gear,tool,[1,2,3]);await frame_model(repair,carousel)
		await snap("repair-three-"+String(tool))
	var before:=gear.capture_state();gear.complete_step(&"cone");await snap("repair-checkpoint")
	gear.restore_state(before);await snap("repair-restored")
	carousel.bind_equipment(gear,&"cone",[3]);await snap("repair-one")
	carousel.bind_equipment(gear,&"cone",[2,3]);await snap("repair-two")
	root.size=Vector2i(640,360);await settle()
	repair.preview_rect=Rect2(280,20,720,620);repair._update_layout();await settle()
	carousel.bind_equipment(gear,&"cone",[1,2,3]);await frame_model(repair,carousel);await snap("repair-small")
	repair.viewport_container.queue_free();repair.queue_free();carousel.queue_free();background.queue_free();await settle();root.size=Vector2i(1280,800)
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("25251f");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=.8;world.add_child(environment)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,8,12);camera.look_at(Vector3(0,1,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=12;camera.current=true
	var light:=DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=Vector3(-40,-25,0)
	var enemy:=CombatPatternEnemy.new();world.add_child(enemy);enemy.configure(&"loop",Vector3.ZERO,3);enemy.facing=Vector3.FORWARD
	await snap("pattern-quiet")
	enemy.pattern_visual.set_instruction_visible(true);await snap("pattern-cut")
	var points:Array[Vector3]=enemy.cable_world_points()
	for i in range(points.size()/2):enemy.receive_attack(&"ring",36,points[i*2],{"segment_start":points[i*2],"segment_end":points[i*2+1],"radius":.01,"already_hit":i>0})
	await snap("pattern-yellow")
	enemy.configure(&"final_boss",Vector3.ZERO,4);enemy.pattern_visual.set_instruction_visible(true);await snap("pattern-pair-a")
	shot(enemy,enemy.valve_world_position(0));await snap("pattern-pair-b")
	enemy.queue_free();await settle()
	var part:=CombatPartVisual.new();world.add_child(part);part.build(&"open",&"front",.8,StandardMaterial3D.new());part.sync(false,false,false,0);part.set_instruction_visible(true);await snap("part-closed")
	part.sync(true,true,false,0);await snap("part-yellow")
	for setting in saved:state.set_setting(setting,saved[setting])
	print(JSON.stringify({"status":"passed","views":pictures.size(),"failures":[]}));quit(0)
