@tool
@icon("../icons/VisionCone3D.svg")
class_name VisionCone3D
extends Area3D
## Provides a "Vision Cone", a cone-shaped area where objects are then probed for visibility via ray casts

const VisionConeDebugVisualizer3D := preload("./debug/VisionConeDebugVisualizer3D.gd")

#region VisionCone3D

#region members
## Emitted when a body is newly visible
signal body_sighted(body: Node3D)

## Emitted when a body is newly not visible
signal body_hidden(body: Node3D)

## Emitted when the cone shape changes
signal shape_changed

## Determines how visibility is probed for bodies within the cone area
##
enum VisionTestMode{
	## Samples the center of each CollisionShape. Maximum performance, least reliability
	SAMPLE_CENTER,
	## Samples random vertices of each CollisionShape, up to `vision_test_shape_max_probe_count` for hidden objects
	## If shape was visible at last frame, tests last successful probe position first
	SAMPLE_RANDOM_VERTICES,
	## Gets a list of points where shapes collide from the physics engine
	# SAMPLE_COLLIDE_SHAPE,
}

## Distance that can be seen (the height of the vision cone)
@warning_ignore("shadowed_global_identifier")
@export var range := 20.0:
	set(v): range = v; _update_shape()

## Angle of the vision cone
@export_range(0, 150) var angle := 45.0:
	set(v): angle = v; _update_shape()

## Whether or not to draw debug information
@export var debug_draw := false:
	set(v):
		debug_draw = v
		if debug_draw and !_debug_visualizer:
			_debug_visualizer = VisionConeDebugVisualizer3D.new()
			add_child(_debug_visualizer)
		elif !debug_draw and _debug_visualizer:
			_debug_visualizer.queue_free()

@export_group("Vision Test", "vision_test_")

## Which VisionTestMode to use to determine if a shape is visible
@export var vision_test_mode : VisionTestMode = VisionTestMode.SAMPLE_RANDOM_VERTICES
## List of bodies to ignore in vision probing
##
## Useful for eg the VisionCone3D's parent body
@export var vision_test_ignore_bodies : Array[PhysicsBody3D]

@export_subgroup("Per-frame probe settings")
## Maximum amount of shape probes (per shape, per frame)
@export var vision_test_shape_max_probe_count : int = 5
## Maximum number of bodies to check, per-frame
##
## All bodies will still be evaluated as it will cycle through them
## frame by frame, but `body_sighted` or `body_hidden` may lag behind
## by some frames.
@export var vision_test_max_body_count : int = 10

@export_group("Collision", "collision_")
## Collision layer "hoisted" up from Area3D for convenience
@export_flags_3d_physics var collision_layer_ : int = 1:
	get:
		return collision_layer
	set(value):
		collision_layer = value

## Collision mask "hoisted" up from Area3D for convenience
## 
## This represents what can be "seen" and notified against. Generally useful for characters
@export_flags_3d_physics var collision_mask_ : int = 1:
	get:
		return collision_mask
	set(value):
		collision_mask = value

## Collision mask of what objects can obscure visible objects (but don't need to
## be tracked and probed to determine visibility)
## 
## Generally useful for the environment but any node where you don't care
## if its seen or not can be on this layer.
## This layer only affects raycasts, which can collide with any layer
## in either `collision_mask` or `collision_environment_mask`
@export_flags_3d_physics var collision_environment_mask : int = 1

## Radius at the wide end of the vision cone
var end_radius: float:
	get: return _get_end_radius()

# { Node3D "body" : Node3D "shape" }
var _body_probe_data : Dictionary = {
	# Node3D "body" : [
		# "prober": VisionTestProber
	# ]
}

var _last_probed_index : int = -1
var _debug_visualizer : VisionConeDebugVisualizer3D
var _collision_shape := CollisionShape3D.new()
var _cone_shape := ConeShape3D.new()

#endregion members

## Returns a list of intersecting PhysicsBody3Ds. The overlapping body's CollisionObject3D.collision_layer must be part of this area's CollisionObject3D.collision_mask in order to be detected.
func get_visible_bodies() -> Array[PhysicsBody3D]:
	var bodies := []
	for prober: VisionTestProber in _body_probe_data.values():
		bodies.push_back(prober.body)
	return bodies

## Whether or not a given point in global space is within the cone's
## angle. 
func point_within_angle(global_point: Vector3) -> bool:
	var body_pos := -global_basis.z
	var pos := global_point - global_position
	var angle_to := pos.angle_to(body_pos)
	var angle_deg := rad_to_deg(angle_to)
	return angle_deg <= (angle / 2)

## Whether or not a given point in global space is within the cone
func point_within_cone(global_point: Vector3) -> bool:
	var local_point := to_local(global_point)
	var z_distance := abs(local_point.z)
	if z_distance < 0 or z_distance > range:
		return false
	return point_within_angle(global_point)

func _init() -> void:
	add_child(_collision_shape)
	_collision_shape.shape = _cone_shape
	_collision_shape.rotation_degrees.x = 90
	_update_shape()
	# only true when copied
	if _debug_visualizer:
		_debug_visualizer.vision_cone = self

	body_shape_entered.connect(_on_body_shape_entered)
	body_shape_exited.connect(_on_body_shape_exited)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if !monitoring:
		return

	var bodies_to_probe := _get_bodies_to_probe_this_frame()
	for body in bodies_to_probe:
		if !is_instance_valid(body):
			push_warning("erasing invalid body")
			_body_probe_data.erase(body)
			continue
		_probe_body(body)
	
func _get_bodies_to_probe_this_frame() -> Array: # Array[CollisionObject3D]:
	var all_bodies := _body_probe_data.keys()
	if all_bodies.is_empty():
		return []
	if all_bodies.size() < vision_test_max_body_count:
		_last_probed_index = -1
		return all_bodies

	var start_index := _last_probed_index + 1
	var to_end := all_bodies.slice(start_index, start_index + vision_test_max_body_count)
	var counted := to_end.size()
	var end_index : int = min(vision_test_max_body_count - counted, start_index)
	var from_start := all_bodies.slice(0, end_index)
	_last_probed_index = from_start.size() - 1 if from_start.size() > 0 else start_index + counted - 1
	return (to_end + from_start)

func _probe_body(body: CollisionObject3D):
	var body_was_visible_last_frame := false
	var body_is_visible := false
	var body_probes : Array[VisionTestProber]
	body_probes.assign(_body_probe_data[body])

	for prober in body_probes:
		if prober.visible:
			body_was_visible_last_frame = true
		prober.probe()
		if prober.visible:
			body_is_visible = true

	var body_visibility_changed := body_is_visible != body_was_visible_last_frame

	if body_visibility_changed:
		if body_is_visible:
			body_sighted.emit(body)
		else:
			body_hidden.emit(body)

func _update_shape() -> void:
	_cone_shape.height = range
	_cone_shape.radius = end_radius
	_collision_shape.position.z = -range / 2
	update_gizmos()
	shape_changed.emit()

func _get_collision_shape_node_in_body(body: PhysicsBody3D, body_shape_index: int) -> Node3D:
	if !body:
		return null
	var body_shape_owner : int = body.shape_find_owner(body_shape_index)
	return body.shape_owner_get_owner(body_shape_owner)

func _get_end_radius() -> float:
	var angle_rad := deg_to_rad(angle / 2)
	return range * tan(angle_rad)

func _get_prober_for_shape(shape: CollisionShape3D, body: CollisionObject3D) -> VisionTestProber:
	for prober in _body_probe_data[body]:
		if prober.collision_shape == shape:
			return prober
	return null

func _on_body_shape_entered(
	_body_rid: RID,
	body: Node3D,
	body_shape_index: int,
	_local_shape_index: int,
) -> void:
	# # weird!
	if !is_instance_valid(body):
		if _body_probe_data.has(body):
			_body_probe_data.erase(body)
		return
	var shape := _get_collision_shape_node_in_body(body, body_shape_index)
	var body_probes := _body_probe_data.get_or_add(body, [])

	var has_prober := _get_prober_for_shape(shape, body)
	if !has_prober:
		body_probes.push_back(VisionTestProber.new(self, shape, body))
	else:
		push_warning("Already has prober")

func _on_body_shape_exited(
	_body_rid: RID,
	body: Node3D,
	body_shape_index: int,
	_local_shape_index: int,
) -> void:
	if !body:
		return
	var shape := _get_collision_shape_node_in_body(body, body_shape_index)
	var prober := _get_prober_for_shape(shape, body)
	_body_probe_data[body].erase(prober)
	if _body_probe_data[body].is_empty():
		_body_probe_data.erase(body)


#endregion VisionCone3D

class VisionTestProber:
	static var _rng := RandomNumberGenerator.new()
	## Vision cone to probe for
	var vision_cone : VisionCone3D
	## Collision shape to probe
	var collision_shape: CollisionShape3D
	## Collision shape mesh representation
	var shape_probe_mesh: ArrayMesh
	## Collision shape's owning body
	var body : PhysicsBody3D

	## Useful for debugging probes
	const CONTINUE_PROBING_ON_SUCCESS := false

	## Whether the probe found the shape to be visible
	var visible: bool = false
	## All probe results, for debugging
	var probe_results: Array[ProbeResult]

	func _init(
		vision_cone_: VisionCone3D,
		collision_shape_: CollisionShape3D,
		body_: PhysicsBody3D
	):
		vision_cone = vision_cone_
		collision_shape = collision_shape_
		shape_probe_mesh = collision_shape_.shape.get_debug_mesh()
		body = body_
	
	func _probe_position(to: Vector3, shape_local_target: Vector3) -> ProbeResult:
		# Collide with bodies OR the environment
		var raycast_collision_mask := vision_cone.collision_mask | vision_cone.collision_environment_mask
		# can store reference to this?
		var space_state := vision_cone.get_world_3d().direct_space_state
		var from := vision_cone.global_position
		var exclude_bodies := vision_cone.vision_test_ignore_bodies\
			.filter(func(x): return is_instance_valid(x))\
			.map(func(x): return x.get_rid())
		var query := PhysicsRayQueryParameters3D.create(
			from,
			to,
			raycast_collision_mask,
			exclude_bodies
		)
		var result := space_state.intersect_ray(query)
		return ProbeResult.new(
			from,
			to,
			shape_local_target,
			result.collider if result.has("collider") else null
		)
	
	func _get_last_visible_point_on_shape() -> Vector3:
		if probe_results.is_empty():
			push_warning("Attempting to find the last visible point on a shape but the shape was not determined to be visible during last _probe_position")
			return Vector3.ZERO
		return probe_results[-1].shape_local_target

	func _random_points_on_probe_mesh(count: int) -> Array[Vector3]:
		var surface_count := shape_probe_mesh.get_surface_count()
		var vertices = shape_probe_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var points : Array[Vector3] = []
		for point in count:
			points.push_back(vertices[_rng.randi_range(0, vertices.size() - 1)])
		return points
	
	func _get_scatter_points(count: int):
		var sample_points : Array[Vector3] = []
		var random_point_count := vision_cone.vision_test_shape_max_probe_count
		sample_points.append_array(_random_points_on_probe_mesh(random_point_count))
		return sample_points
	
	func _get_collide_points(count: int):
		var sample_points : Array[Vector3] = []
		var cone_shape := vision_cone._collision_shape.shape
		var observable_shape := collision_shape.shape
		var query := PhysicsShapeQueryParameters3D.new()
		query.collide_with_areas = true
		query.collide_with_bodies = false
		query.collision_mask = vision_cone.collision_layer
		query.shape_rid = observable_shape.get_rid()

		var world_space := vision_cone.get_world_3d().direct_space_state
		var result := world_space.collide_shape(query)
		for i in result.size():
			if i % 2 == 1:
				continue
			sample_points.push_back(result[i])
			if sample_points.size() >= count:
				break
		return sample_points
		
	func probe():
		var sample_points : Array[Vector3] = []
		var max_count := vision_cone.vision_test_shape_max_probe_count
		if visible:
			sample_points.append(_get_last_visible_point_on_shape())
			max_count -= 1
		match vision_cone.vision_test_mode:
			VisionTestMode.SAMPLE_CENTER:
				if !visible:
					sample_points.push_back(Vector3.ZERO)
			VisionTestMode.SAMPLE_RANDOM_VERTICES: 
				sample_points.append_array(_get_scatter_points(max_count))

		probe_results = []
		visible = false
		for shape_local_point in sample_points:
			var global_point := collision_shape.global_position + (collision_shape.global_basis * shape_local_point)

			if !vision_cone.point_within_cone(global_point):
				continue

			var probe_result := _probe_position(global_point, shape_local_point)
			probe_results.push_back(probe_result)

			# found body we were looking for
			if probe_result.collider == body:
				probe_result.visible = true
				visible = true
				if CONTINUE_PROBING_ON_SUCCESS:
					print_debug("visible - continuing to _probe_position")
					continue
				return


	class ProbeResult:
		var start : Vector3
		var end : Vector3
		var shape_local_target : Vector3
		var collider : Node3D
		var visible : bool = false

		func _init(
			start_: Vector3,
			end_: Vector3,
			shape_local_target_: Vector3,
			collider_: Node3D
		):
			start = start_
			end = end_
			shape_local_target = shape_local_target_
			collider = collider_
