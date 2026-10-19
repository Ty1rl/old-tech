extends Node3D
# The menu is a real view of the same museum materials used in play.
const Museum = preload("res://scenes/prototype/museum_environment.gd")

func _ready() -> void:
	var museum := Museum.new()
	add_child(museum)
	museum.build(false)
	var camera := Camera3D.new()
	camera.position = Vector3(8, 12, 14)
	camera.rotation_degrees = Vector3(-40, 20, 0)
	camera.fov = 48
	camera.current = true
	add_child(camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("11100d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7a483")
	environment.environment.ambient_light_energy = 0.25
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	light.light_color = Color("f5d6a2")
	light.light_energy = 0.8
	light.shadow_enabled = true
	add_child(light)
	for point in [Vector3(-5,4,-5),Vector3(7,4,2)]:
		var lamp := OmniLight3D.new()
		lamp.position = point
		lamp.light_color = Color("ffd08a")
		lamp.light_energy = 2
		lamp.omni_range = 12
		add_child(lamp)
	for point in [Vector3(3,0,-2),Vector3(8,0,-5),Vector3(-3,0,-5)]:
		_box(point+Vector3.UP*0.7,Vector3(2,1.4,2),Color("454035"))
		_box(point+Vector3.UP*1.45,Vector3(2.15,.12,2.15),Color("b7a483"))
		var object := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = .55; torus.outer_radius = .85
		object.mesh = torus
		object.position = point+Vector3.UP*2.4
		object.rotation_degrees = Vector3(70,35,0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("7f7054")
		material.metallic = .65; material.roughness = .5
		object.material_override = material
		add_child(object)
		_box(point+Vector3(0,1.75,0),Vector3(.24,.5,.24),Color("34312b"))

func _box(at: Vector3, dimensions: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	geometry.size = dimensions
	instance.mesh = geometry
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .7
	instance.material_override = material
	add_child(instance)
