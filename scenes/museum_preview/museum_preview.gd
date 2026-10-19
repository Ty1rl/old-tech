extends Node3D

var arena: Node3D
var museum: Node3D

func _ready() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	add_child(arena)
	museum = arena.museum
