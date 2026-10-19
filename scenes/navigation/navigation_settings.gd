class_name EnemyNavigationSettings
extends Resource
## Read-only route/follow settings. Actor state belongs to the native agents.
@export var clearance_buckets := PackedFloat32Array([.8, 1.25, 2.1, 3.7])
@export_range(.05, 1, .01) var cell_size := .2
@export_range(.01, .5, .01) var clearance_padding := .10
@export_range(.1, 1, .01) var repath_interval := .3
@export_range(.1, 2, .01) var target_motion_threshold := .65
@export_range(.05, .5, .01) var waypoint_distance := .16
@export_range(.01, .5, .01) var target_distance := .10
@export_range(.1, 2, .01) var path_deviation := .8

@export_range(1, 16, 1) var avoidance_max_neighbors := 8
@export_range(1, 8, .1) var avoidance_neighbor_distance := 3.0
@export_range(.1, 2, .1) var avoidance_horizon := .6
