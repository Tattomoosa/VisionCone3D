@tool
extends Node3D

@export var observable_count : int = 5000
@export var size : Vector3 = Vector3.ONE

var _observable_box_shape := BoxShape3D.new()
var _observables : Array[Node3D] = []
var _rng := RandomNumberGenerator.new()

@onready var physics_fps_label : Label = %PhysicsFPS

func _ready():
	if Engine.is_editor_hint():
		return

	for _i in observable_count:
		_observables.push_back(_create_observable())

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	for ob in _observables:
		ob.position = Vector3(
			(_rng.randf() - 0.5) * size.x,
			(_rng.randf() - 0.5) * size.y,
			(_rng.randf() - 0.5) * size.z,
		)

		var physics_frame_time := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var physics_max_frame_time : float = 1.0 / ProjectSettings.get_setting("physics/common/physics_ticks_per_second")

		physics_fps_label.text = "Physics Frame: " + str(snapped(physics_frame_time / physics_max_frame_time, 0.01) * 100.0) + "%"

func _create_observable() -> Node3D:
	var node := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = _observable_box_shape
	node.add_child(collision_shape)
	add_child(node)
	return node
