extends Node

# One safe specimen in the actual baseline arena, only for tutorial review.
# The campaign supplies its own world/action guards and success observations.
var arena: Node3D
var tutorial: Control
var specimen: Node3D

func _ready() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	add_child(arena)
	arena.director.clear()
	specimen = arena.director.spawn(&"blue", Vector3(0, 0, -5))
	specimen.move_speed = 0
	specimen.contact_damage = 0
	# Let the real camera/HUD establish their first rendered positions.
	await get_tree().process_frame
	await get_tree().process_frame
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	tutorial = load("res://scenes/ui/tutorial.gd").new()
	layer.add_child(tutorial)
	tutorial.setup(arena.player.camera)
	tutorial.blocking_changed.connect(func(value: bool): arena.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT)
	tutorial.show_known_lesson(&"cut", specimen.cable_world_points())

func _process(_delta: float) -> void:
	if tutorial and tutorial.practicing and is_instance_valid(specimen) and specimen.cable_cut:
		tutorial.complete_lesson(&"cut")
