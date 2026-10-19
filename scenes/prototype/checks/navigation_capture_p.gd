extends SceneTree
const Trial = preload("res://scenes/navigation/checks/fixture.gd")
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-5/exports/round-p-a/"
var trial: Node3D
var label: Label
var line: MeshInstance3D
var images: Array[String] = []
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func path_line(points: Array[Vector3], color: Color) -> void:
	var mesh := ImmediateMesh.new()
	if points.size()>1:
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(points.size()-1):
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(points[i]+Vector3.UP*.12)
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(points[i+1]+Vector3.UP*.12)
		mesh.surface_end()
	line.mesh=mesh
func picture(name: String, text: String) -> void:
	label.text=text+"\nPrivate navigation trial · matching collider/region exhibits · current models"
	await process_frame
	await RenderingServer.frame_post_draw
	var path:=name+".png"
	if root.get_texture().get_image().save_png(OUT+path)==OK: images.append(path)
	else: failures.append("save "+name)
func run() -> void:
	trial=Trial.new()
	root.add_child(trial)
	var camera:=Camera3D.new()
	trial.add_child(camera)
	camera.position=Vector3(24,38,31)
	camera.look_at(Vector3(0,0,0))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=43
	camera.current=true
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-60,-25,0)
	trial.add_child(light)
	var world:=WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color("1e242b")
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color=Color.WHITE
	world.environment.ambient_light_energy=.6
	trial.add_child(world)
	var layer:=CanvasLayer.new()
	label=Label.new()
	label.position=Vector2(20,20)
	label.add_theme_font_size_override("font_size",21)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	layer.add_child(label)
	trial.add_child(layer)
	line=MeshInstance3D.new()
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo=true
	line.material_override=material
	trial.add_child(line)
	trial.director.navigation.sync_region()
	for i in range(180):
		await physics_frame
		if trial.ready_maps(): break
	if not trial.ready_maps():
		failures.append("native maps not ready")
	else:
		var actor: CombatEnemy=trial.director.spawn(&"blue",Vector3(0,0,-12))
		var trace: Array[Vector3]=[actor.position]
		await picture("route-start","Blue approach · three staggered exhibits · no direct walkable segment")
		for i in range(150):
			trial.director.step(.08,trial.player)
			if i%2==0: trace.append(actor.position)
			await physics_frame
		path_line(trace,Color("e7e1ce"))
		await picture("route-detour","Actual native route trace · no hand-written corner selector or point snapping")
		var saved: Dictionary=trial.director.capture_state()
		for i in range(30):
			trial.director.step(.05,trial.player)
			await physics_frame
		trial.director.restore_state(saved)
		for i in range(6):
			trial.director.step(0,trial.player)
			await physics_frame
		await picture("route-rewind","Rewound world pose · route is rebuilt from intent · zero agent updates during scrub")
		trial.director.clear()
		line.mesh=null
		var wide: CombatPatternEnemy=trial.director.spawn(&"loop",Vector3(0,0,-12))
		trace=[wide.position]
		for i in range(190):
			trial.director.step(.1,trial.player)
			if i%2==0: trace.append(wide.position)
			await physics_frame
		path_line(trace,Color("59baff"))
		await picture("wide-clearance","Wide pattern uses its full support silhouette · separate native clearance mesh")
		trial.director.clear()
		line.mesh=null
		for z in range(4):
			for x in range(8): trial.director.spawn([&"blue",&"yellow",&"orange"][(x+z)%3],Vector3(x*3-11,0,-16+z*2))
		for i in range(150):
			trial.director.step(.08,trial.player)
			await physics_frame
		await picture("crowd-32","32 native agents · bounded local separation · natural packs/files and an escape side")
	var result: Dictionary={"status":"passed" if failures.is_empty() else "failed","checks":images.size(),"failures":failures,"images":images}
	FileAccess.open(OUT+"visuals.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	trial.queue_free()
	await process_frame
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
