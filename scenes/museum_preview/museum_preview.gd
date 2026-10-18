extends Node3D

const MuseumEnvironment = preload("res://scenes/prototype/museum_environment.gd")

var arena: Node3D
var museum: Node3D


func _ready() -> void:
	var arena_scene := load("res://scenes/prototype/arena.tscn") as PackedScene
	arena = arena_scene.instantiate()
	add_child(arena)
	museum = MuseumEnvironment.new()
	museum.name = "MuseumEnvironment"
	museum.build()
	museum.apply_to_arena(arena, true)
