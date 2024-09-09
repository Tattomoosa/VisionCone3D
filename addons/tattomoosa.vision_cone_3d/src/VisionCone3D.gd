@tool
@icon("../icons/VisionCone3D.svg")
class_name VisionCone3D
extends Node3D
## Provides a "Vision Cone", a cone-shaped area where objects are then probed for visibility via ray casts

## Emitted when a body is newly visible
signal body_sighted(body: Node3D)

## Emitted when a body is newly not visible
signal body_hidden(body: Node3D)

## Emitted when the cone shape changes
signal shape_changed

enum VisionTestMode{
	## Samples the center of each CollisionShape
	SAMPLE_CENTER,
	## Samples random vertices of each CollisionShape, up to `vision_test_shape_max_probe_count` for hidden objects
	## If shape was visible at last frame, tests last successful probe position first
	SAMPLE_RANDOM_VERTICES
}

## Distance that can be seen (the height of the vision cone)
@warning_ignore("shadowed_global_identifier")
@export var range := 20.0:
	set(v): range = v; _update_shape()

## Angle of the vision cone
@export var angle := 45.0:
	set(v): angle = v; _update_shape()

@export var monitoring := true:
	set(value):
		monitoring = value
		if _cone_area:
			_cone_area.monitoring = value

## Whether or not to draw debug information
@export var debug_draw := false:
	set(v):
		debug_draw = v
		if debug_draw and !_debug_visualizer:
			add_child(VisionConeDebugVisualizer3D.new())
		elif !debug_draw and _debug_visualizer:
				_debug_visualizer.queue_free()

@export_group("Vision Test", "vision_test_")

## Which VisionTestMode to use to determine if a shape is visible
@export var vision_test_mode : VisionTestMode = VisionTestMode.SAMPLE_RANDOM_VERTICES
## Maximum amount of shape probes (per shape, per frame)
@export var vision_test_shape_max_probe_count : int = 5
## Maximum number of bodies to check, per-frame
@export var vision_test_max_bodies : int = 50

## List of bodies to ignore in vision probing
##
## Useful for eg the VisionCone3D's parent body
@export var vision_test_ignore_bodies : Array[PhysicsBody3D]

@export_group("Collision", "collision_")
## Collision layer of the vision cone
@export_flags_3d_physics var collision_layer : int = 1:
	set(value):
		collision_layer = value
		if is_node_ready():
			_cone_area.collision_layer = collision_layer

## Collision mask of the vision cone (Tracked and considered "visible")
## 
## Generally useful for characters
@export_flags_3d_physics var collision_mask : int = 1:
	set(value):
		collision_mask = value
		if is_node_ready():
			_cone_area.collision_mask = collision_mask

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
	get: return _cone_area.end_radius

# Determines whether shapes are inside the cone or not
var _cone_area : ConeArea3D = ConeArea3D.new()

# List of shapes currently in cone
var _shapes_in_cone : Array[Node3D] = []

# shape probes, mapped by collision shape
# { Node3D "shape" : VisionTestProber }
var _shape_probe_data : Dictionary = {}
# Shapes, mapped by body
# { Node3D "body" : Node3D "shape" }
var _body_shape_data : Dictionary = {}

var _last_probed_index : int = -1

var _debug_visualizer : VisionConeDebugVisualizer3D

func _init() -> void:
	add_child(_cone_area)
	_update_shape()
	# only true when copied
	if _debug_visualizer:
		_debug_visualizer.vision_cone = self

	_cone_area.collision_layer = collision_layer
	_cone_area.collision_mask = collision_mask
	_cone_area.body_shape_entered.connect(_on_body_shape_entered)
	_cone_area.body_shape_exited.connect(_on_body_shape_exited)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var bodies_to_probe := _get_bodies_to_check_this_frame()
	for body in bodies_to_probe:
		_update_body_probes(body)
	
func _get_bodies_to_check_this_frame() -> Array: # Array[CollisionObject3D]:
	var all_bodies := _body_shape_data.keys()
	if all_bodies.is_empty():
		return []
	if all_bodies.size() < vision_test_max_bodies:
		_last_probed_index = -1
		return all_bodies
	var start_index := _last_probed_index + 1
	var to_end := all_bodies.slice(start_index, start_index + vision_test_max_bodies)
	var counted := to_end.size()
	var end_index := min(vision_test_max_bodies - counted, start_index)
	var from_start := all_bodies.slice(0, end_index)
	_last_probed_index = from_start.size() - 1 if from_start.size() > 0 else start_index + counted
	return (to_end + from_start)

	# var index_offset := start_index
	# var indexes_to_check : Array[int] = []
	# for i: int in min(vision_test_max_bodies, all_bodies.size()):
	# 	var index := index_offset + i
	# 	if index >= all_bodies.size():
	# 		index_offset = -index + 1
	# 		index = 0
	# 	indexes_to_check.push_back(index)
	# _last_probed_index = indexes_to_check[-1]
	# var bodies_to_check : Array[CollisionObject3D]= []
	# for i in indexes_to_check:
	# 	bodies_to_check.push_back(all_bodies[i])
	# return bodies_to_check

func _update_body_probes(body: CollisionObject3D):
	var shapes : Array[Node3D] = _body_shape_data[body]
	var body_was_visible_last_frame := false
	var body_is_visible := false

	for shape in shapes:
		var prober : VisionTestProber = _shape_probe_data[shape]
		if prober.visible:
			body_was_visible_last_frame = true
		prober.update()
		if prober.visible:
			body_is_visible = true

	var body_visibility_changed := body_is_visible != body_was_visible_last_frame

	if body_visibility_changed:
		if body_is_visible:
			body_sighted.emit(body)
		else:
			body_hidden.emit(body)

func _update_shape() -> void:
	_cone_area.range = range
	_cone_area.angle = angle
	update_gizmos()
	shape_changed.emit()

func get_visible_bodies() -> Array[PhysicsBody3D]:
	var bodies := []
	for prober: VisionTestProber in _shape_probe_data.values():
		bodies.push_back(prober.body)
	return bodies

func _get_collision_shape_node_in_body(body: PhysicsBody3D, body_shape_index: int) -> Node3D:
	var body_shape_owner : int = body.shape_find_owner(body_shape_index)
	return body.shape_owner_get_owner(body_shape_owner)

func _on_body_shape_entered(
	_body_rid: RID,
	body: Node3D,
	body_shape_index: int,
	_local_shape_index: int,
) -> void:
	var shape := _get_collision_shape_node_in_body(body, body_shape_index)
	_shape_probe_data[shape] = VisionTestProber.new(self, shape, body)
	var shape_list : Array[Node3D] = _body_shape_data.get_or_add(body, [] as Array[Node3D])
	shape_list.push_back(shape)

func _on_body_shape_exited(
	_body_rid: RID,
	body: Node3D,
	body_shape_index: int,
	_local_shape_index: int,
) -> void:
	var shape_list : Array[Node3D] = _body_shape_data.get(body, [] as Array[Node3D])
	var shape := _get_collision_shape_node_in_body(body, body_shape_index)
	shape_list.erase(shape)
	if shape_list.is_empty():
		_body_shape_data.erase(body)
	_shapes_in_cone.erase(shape)
	_shape_probe_data.erase(shape)

#endregion VisionCone3D

class ConeArea3D extends Area3D:
	var range : float = 20.0:
		set(value): range = value; _update_shape()
	var angle : float = 45.0:
		set(value): angle = value; _update_shape()
	var end_radius : float:
		get:
			return _get_end_radius()
	
	var _cylinder_shape_mesh := CylinderMesh.new()
	var _collision_shape := CollisionShape3D.new()
	
	func _init():
		_cylinder_shape_mesh.top_radius = 0
		_cylinder_shape_mesh.rings = 1
		_cylinder_shape_mesh.radial_segments = 16
		_collision_shape.rotation_degrees.x = 90
		add_child(_collision_shape)
		_update_shape()
	
	func _update_shape():
		_cylinder_shape_mesh.bottom_radius = _get_end_radius()
		_cylinder_shape_mesh.height = range
		_collision_shape.position.z = -range / 2
		_collision_shape.shape = _cylinder_shape_mesh.create_convex_shape()
	
	## Whether or not a given point in global space is within the cone's
	## angle. 
	func point_within_angle(global_point: Vector3) -> bool:
		var body_pos := -global_basis.z
		var pos := global_point - global_position
		var angle_to := pos.angle_to(body_pos)
		var angle_deg := rad_to_deg(angle_to)
		return angle_deg <= (angle / 2)
	
	func point_within_cone(global_point: Vector3) -> bool:
		var local_point := to_local(global_point)
		var z_distance := position.z - local_point.z
		if z_distance < 0 or z_distance > range:
			return false
		return point_within_angle(global_point)

	func _get_end_radius() -> float:
		return get_cone_radius(range, angle / 2)

	static func get_cone_radius(height: float, angle_deg: float) -> float:
		return height * tan(deg_to_rad(angle_deg))

class VisionTestProber:
	static var _rng := RandomNumberGenerator.new()
	var vision_cone : VisionCone3D
	var collision_shape: CollisionShape3D
	var shape_probe_mesh: ArrayMesh
	var body : PhysicsBody3D

	var visible: bool = false
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
	
	func probe(to: Vector3, shape_local_target: Vector3) -> ProbeResult:
		# Collide with bodies OR the environment
		var raycast_collision_mask := vision_cone.collision_mask | vision_cone.collision_environment_mask
		# can store reference to this?
		var space_state := vision_cone.get_world_3d().direct_space_state
		var from := vision_cone.global_position
		var exclude_bodies := vision_cone.vision_test_ignore_bodies.map(func(x): x.get_rid())
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
	
	func _random_points_on_probe_mesh(count: int) -> Array[Vector3]:
		var surface_count := shape_probe_mesh.get_surface_count()
		var vertices = shape_probe_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var points : Array[Vector3] = []
		for point in count:
			points.push_back(vertices[_rng.randi_range(0, vertices.size() - 1)])
		return points
	
	func _get_scatter_points():
		var sample_points : Array[Vector3] = []
		var random_point_count := vision_cone.vision_test_shape_max_probe_count
		if !probe_results.is_empty():
			var last := probe_results[-1]
			if last.visible:
				sample_points.append(last.shape_local_target)
				random_point_count -= 1
		sample_points.append_array(_random_points_on_probe_mesh(random_point_count))
		return sample_points
		
	func update():
		var sample_points : Array[Vector3] = []
		match vision_cone.vision_test_mode:
			VisionTestMode.SAMPLE_CENTER:
				sample_points = [Vector3.ZERO]
			VisionTestMode.SAMPLE_RANDOM_VERTICES: 
				sample_points = _get_scatter_points()

		probe_results = []
		visible = false
		for shape_local_point in sample_points:
			var global_point := collision_shape.global_position + (collision_shape.global_basis * shape_local_point)
			# TODO this check should happen in _get_scatter_points maybe?
			# ensure more points actually intersect objects midway through?
			# not sure it matters...
			if !vision_cone._cone_area.point_within_cone(global_point):
				continue

			var probe_result := probe(global_point, shape_local_point)
			probe_results.push_back(probe_result)

			# found body we were looking for
			if probe_result.collider == body:
				probe_result.visible = true
				visible = true
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

class VisionConeDebugVisualizer3D extends Node3D:

	# TODO should be modifiable via EditorSettings
	const DEBUG_VISION_CONE_COLOR := Color(1, 1, 0, 0.02)
	# TODO should be modifiable via EditorSettings
	const DEBUG_RAY_COLOR_IS_VISIBLE := Color(Color.GREEN, 0.5)
	# TODO should be modifiable via EditorSettings
	const DEBUG_RAY_COLOR_IS_OBSTRUCTED := Color(Color.RED, 0.2)

	static var debug_vision_cone_color := DEBUG_VISION_CONE_COLOR
	static var debug_ray_color_is_visible := DEBUG_RAY_COLOR_IS_VISIBLE
	static var debug_ray_color_in_cone := DEBUG_RAY_COLOR_IS_OBSTRUCTED

	@export var vision_cone : VisionCone3D

	var _bounds_renderer : MeshInstance3D
	var _probe_renderer : DebugProbeLineRenderer

	func _init():
		# create cone renderer
		_bounds_renderer = MeshInstance3D.new()
		_bounds_renderer.mesh = CylinderMesh.new()
		_bounds_renderer.mesh.material = make_visualizer_material()
		add_child(_bounds_renderer, false, INTERNAL_MODE_BACK)

		_probe_renderer = DebugProbeLineRenderer.new()
		add_child(_probe_renderer)
	
	func _ready():
		vision_cone = get_parent()
		_probe_renderer.probe_data = vision_cone._shape_probe_data
		vision_cone.shape_changed.connect(update_cone_shape)
		update_cone_shape()

	static func make_visualizer_material(albedo_color: Color = debug_vision_cone_color) -> StandardMaterial3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = albedo_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return mat
	
	func update_cone_shape() -> void:
		var m : CylinderMesh = _bounds_renderer.mesh
		m.top_radius = 0
		m.bottom_radius = vision_cone.end_radius
		m.height = vision_cone.range
		_bounds_renderer.rotation_degrees = Vector3(90, 0, 0)
		_bounds_renderer.position.z = -vision_cone.range / 2
	
	class DebugProbeLineRenderer extends MeshInstance3D:
		const ProbeResult := VisionTestProber.ProbeResult
		var probe_data: Dictionary
		var probe_success_material : StandardMaterial3D
		var probe_failure_material : StandardMaterial3D

		func _init():
			mesh = ImmediateMesh.new()
			probe_success_material = VisionConeDebugVisualizer3D.make_visualizer_material(
				VisionConeDebugVisualizer3D.debug_ray_color_is_visible)
			probe_failure_material = VisionConeDebugVisualizer3D.make_visualizer_material(
				VisionConeDebugVisualizer3D.debug_ray_color_in_cone)

		func _process(_delta: float):
			if Engine.is_editor_hint():
				return
			mesh.clear_surfaces()
			if probe_data.is_empty():
				return
			var successful : Array[ProbeResult] = []
			var failed : Array[ProbeResult] = []

			for prober in probe_data.values():
				for probe in prober.probe_results:
					if probe.visible:
						successful.push_back(probe)
					else:
						failed.push_back(probe)
			
			var material_index := 0
			if !successful.is_empty():
				_add_probe_lines_surface(successful)
				mesh.surface_set_material(material_index, probe_success_material)
				material_index += 1
			if !failed.is_empty():
				_add_probe_lines_surface(failed)
				mesh.surface_set_material(material_index, probe_failure_material)
				material_index += 1
		
		func _add_probe_lines_surface(probes: Array[ProbeResult]):
			mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			for probe in probes:
				mesh.surface_add_vertex(to_local(probe.start))
				mesh.surface_add_vertex(to_local(probe.end))
			mesh.surface_end()