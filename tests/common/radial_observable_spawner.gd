extends Node3D

@export var vision_cone : VisionCone3D
@export var spawn_count := 100
@export var observable : Node3D

var _spawner : Node3D

var observables : Array[Node3D]
var i : int

func _ready() -> void:
	await get_tree().process_frame
	_spawner = get_child(0)
	for _i in spawn_count:
		var ob := observable.duplicate(DUPLICATE_SIGNALS)
		get_parent().add_child(ob)
		ob.show()
		observables.push_back(ob)
	observable.queue_free()
	i = 0
	_range_changed(20.0)
	# _range_changed()
	# distance.value_changed.connect(_range_changed.unbind(1))

func _range_changed(distance_value: float) -> void:
	_spawner.position.z = -distance_value
	var _rotation_amount := 360.0 / spawn_count
	for ob in observables:
		ob.global_position = _spawner.global_position
		rotation_degrees.y += _rotation_amount
		ob.look_at(global_position)