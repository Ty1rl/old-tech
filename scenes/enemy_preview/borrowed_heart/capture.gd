extends SceneTree

const MODEL = "res://assets/enemies/borrowed_heart/borrowed_heart.glb"
const OUT = "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-7/exports/round-j"
var world: Node3D
var subject: Node3D
var camera: Camera3D
var pass_id: String
var title: Label

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	pass_id = FileAccess.get_file_as_string(OUT + "/pass.txt").strip_edges()
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("222b30")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d6dce1")
	settings.ambient_light_energy = 0.5
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = settings
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 145, 0)
	sun.light_color = Color("ffe2bb")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, -35, 0)
	rim.light_color = Color("8ca9c9")
	rim.light_energy = 0.35
	world.add_child(rim)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("394348")
	mat.roughness = 0.92
	ground.material_override = mat
	ground.position.y = -0.01
	world.add_child(ground)
	subject = load(MODEL).instantiate()
	world.add_child(subject)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	world.add_child(camera)
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	title = Label.new()
	title.position = Vector2(34, 26)
	title.add_theme_font_size_override("font_size", 24)
	canvas.add_child(title)
	await process_frame
	if pass_id == "3":
		var result: Dictionary = load("res://scenes/enemy_preview/borrowed_heart/model_check.gd").new().run(subject)
		print(JSON.stringify(result))
		var receipt := FileAccess.open(OUT + "/asset-checks.json", FileAccess.WRITE)
		receipt.store_string(JSON.stringify(result, "  ") + "\n")
		receipt.close()
		if result.status != "passed":
			push_error("Borrowed Heart checks failed: " + str(result.failures))
			quit(1)
			return
	var anim: AnimationPlayer = subject.find_child("AnimationPlayer", true, false)
	if anim:
		print("Clips: ", anim.get_animation_list())
		anim.active = false
	camera.size = 4.3
	camera.position = Vector3(4.5, 3.1, -7.2)
	camera.look_at(Vector3(0.65, 1.25, 0))
	await snap("close", "BORROWED HEART  /  PASS " + pass_id + "  /  CLOSED")
	if pass_id == "3":
		camera.position = Vector3(-4.4, 2.9, 6.4)
		camera.look_at(Vector3(0.65, 1.25, 0))
		await snap("back", "BORROWED HEART  /  HARNESS + BRACES")
	subject.rotation.y = PI
	camera.size = 22.0
	camera.rotation_degrees = Vector3(-55, 0, 0)
	camera.position = Vector3(-0.7, 15, 10.5)
	await snap("gameplay", "BORROWED HEART  /  ORTHO 22  /  PITCH -55  /  1280 x 800")
	if pass_id == "3":
		subject.rotation.y = 0.0
		camera.size = 4.3
		camera.position = Vector3(4.5, 3.1, -7.2)
		camera.look_at(Vector3(0.65, 1.25, 0))
		subject.find_child("HeatCover",true,false).visible = false
		subject.find_child("CutConduit",true,false).visible = false
		await snap("exposed", "BORROWED HEART  /  COVER REMOVED + CONDUIT CUT")
		subject.rotation.y = PI
		camera.size = 22.0
		camera.rotation_degrees = Vector3(-55, 0, 0)
		camera.position = Vector3(-0.7, 15, 10.5)
		await snap("gameplay-exposed", "BORROWED HEART  /  EXPOSED  /  ORTHO 22  /  PITCH -55")
		subject.rotation.y = 0.0
		camera.size = 4.3
		camera.position = Vector3(4.5, 3.1, -7.2)
		camera.look_at(Vector3(0.65, 1.25, 0))
		subject.find_child("HeatCover",true,false).visible = true
		subject.find_child("CutConduit",true,false).visible = true
		if anim:
			anim.active = true
			anim.play("Walk")
			anim.seek(0.25, true)
			anim.pause()
			await snap("walk", "BORROWED HEART  /  WALK 0.25 s")
	print("Preview capture complete, pass ", pass_id)
	quit(0)

func snap(tag: String, label_text: String) -> void:
	title.text = label_text
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OUT + "/pass-" + pass_id + "-" + tag + ".png"
	var error := root.get_texture().get_image().save_png(path)
	assert(error == OK, "Screenshot save failed")
	print("Saved ", path)
