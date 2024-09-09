extends Node3D

@export var vision_cone : VisionCone3D
@export var observable_count : int = 5000
@export var size : Vector3 = Vector3.ONE
@export_enum("StaticBody3D", "AnimatableBody3D", "CharacterBody3D") var collision_body_type : int

var _observable_box_shape := BoxShape3D.new()
var _observable_box_mesh := BoxMesh.new()
var _observables : Array[Node3D] = []
var _rng := RandomNumberGenerator.new()

@onready var debug_label : Label = %DebugLabel

func _ready():
	if Engine.is_editor_hint():
		return

	for _i in observable_count:
		_observables.push_back(_create_observable())
	for ob in _observables:
		ob.position = Vector3(
			(_rng.randf() - 0.5) * size.x,
			(_rng.randf() - 0.5) * size.y,
			(_rng.randf() - 0.5) * size.z,
		)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var physics_frame_time := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var physics_max_frame_time : float = 1.0 / ProjectSettings.get_setting("physics/common/physics_ticks_per_second")

	debug_label.text = \
		"Observable Count: " + str(_observables.size()) +"\n" +\
		"Shapes in Cone: " + str(vision_cone._shape_probe_data.size()) + "\n" +\
		"Physics Frame: " + str(snapped(physics_frame_time / physics_max_frame_time, 0.01) * 100.0) + "%\n" +\
		"FPS: " + str(Engine.get_frames_per_second()) + "\n" +\
		""

func _create_observable() -> Node3D:
	var node : CollisionObject3D
	match collision_body_type:
		0: node = StaticBody3D.new()
		1: node = AnimatableBody3D.new()
		2: node = CharacterBody3D.new()
	# var node := StaticBody3D.new()
	# var node := AnimatableBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = _observable_box_shape
	node.add_child(collision_shape)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _observable_box_mesh
	node.add_child(mesh_instance)
	add_child(node)
	return node
