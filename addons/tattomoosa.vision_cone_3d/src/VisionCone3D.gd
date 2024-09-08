@tool
@icon("../icons/VisionCone3D.svg")
class_name VisionCone3D
extends Node3D

## Simulates a cone vision shape and also checks to make sure
## object is unobstructed

## Emitted when a body is newly visible
signal body_visible(body: Node3D)

## Emitted when a body is newly hidden
signal body_hidden(body: Node3D)

## Emitted when the cone shape changes
signal shape_changed

enum VisionTestMode{
	## Samples the center of each CollisionShape
	SAMPLE_CENTER,
	## Samples random vertices of each CollisionShape, up to `vision_test_shape_probe_count` for hidden objects
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

## Whether or not to draw debug information
@export var debug_draw := false:
	set(v):
		debug_draw = v
		_debug_visualizer.visible = v

@export_group("Vision Test", "vision_test_")
@export var vision_test_mode : VisionTestMode
@export var vision_test_shape_probe_count : int = 5
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

## Determines whether shapes are inside the cone or not
var _cone_area := ConeArea3D.new()

## List of shapes currently in cone
var _shapes_in_cone : Array[Node3D] = []

## List of shapes currently visible
# var _shapes_visible : Array[Node3D] = []

# { Node3D "shape" : VisionTestProber }
var _shape_probe_data : Dictionary = {}
# { Node3D "body" : Node3D "shape" }
var _body_shape_data : Dictionary = {}

var _debug_visualizer : VisionConeDebugVisualizer3D

func _init() -> void:
	add_child(_cone_area)

	# debug
	_debug_visualizer = VisionConeDebugVisualizer3D.new(self)
	_update_shape()

	_cone_area.collision_layer = collision_layer
	_cone_area.collision_mask = collision_mask
	_cone_area.shape_entered_cone.connect(_on_shape_entered_cone)
	_cone_area.shape_exited_cone.connect(_on_shape_exited_cone)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	for body in _body_shape_data:
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
				body_visible.emit(body)
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

func _on_shape_entered_cone(shape: Node3D, body: PhysicsBody3D):
	if body in vision_test_ignore_bodies:
		return
	_shape_probe_data[shape] = VisionTestProber.new(self, shape, body)
	var shape_list : Array[Node3D] = _body_shape_data.get_or_add(body, [] as Array[Node3D])
	shape_list.push_back(shape)

func _on_shape_exited_cone(shape: Node3D):
	var prober : VisionTestProber = _shape_probe_data.get(shape)
	if prober:
		var body : Node3D = prober.body
		var shape_list : Array[Node3D] = _body_shape_data.get(body, [] as Array[Node3D])
		shape_list.erase(shape)
		if shape_list.is_empty():
			_body_shape_data.erase(body)
	_shapes_in_cone.erase(shape)
	_shape_probe_data.erase(shape)

#endregion VisionCone3D

class ConeArea3D extends Area3D:
	signal shape_entered_cone(collision_shape: Node3D)
	signal shape_exited_cone(collision_shape: Node3D)
	signal cone_changed()

	var range : float = 20.0:
		set(value): range = value; _update_shape()
	var angle : float = 45.0:
		set(value): angle = value; _update_shape()

	var end_radius : float:
		get:
			return _get_end_radius()
	var shapes_in_cone : Array[Node3D]:
		get: return _shapes_in_cone

	var _collision_shape := CollisionShape3D.new()
	var _shapes_in_bounding_box : Array[Node3D] = []
	var _shapes_in_cone : Array[Node3D] = []
	# { Node3D (shape): PhysicsBody3D }
	var _shape_body_map : Dictionary = {}

	func _init() -> void:
		add_child(_collision_shape)
		_collision_shape.shape = CylinderShape3D.new()
		_collision_shape.rotation_degrees.x = 90
		body_shape_entered.connect(_on_body_shape_entered)
		body_shape_exited.connect(_on_body_shape_exited)
	
	func _update_shape():
		_collision_shape.shape.radius = end_radius
		_collision_shape.shape.height = range
		_collision_shape.position.z = -range / 2
		cone_changed.emit()

	func _physics_process(delta: float) -> void:
		for shape in _shapes_in_bounding_box:
			if shape_in_vision_cone(shape):
				if !_shapes_in_cone.has(shape):
					_shapes_in_cone.push_back(shape)
					shape_entered_cone.emit(shape, _shape_body_map[shape])
			else:
				_shapes_in_cone.erase(shape)
				shape_exited_cone.emit(shape)
	
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
			if z_distance < 0:
				print(z_distance)
			return false
		return point_within_angle(global_point)

	func shape_in_vision_cone(shape: Node3D) -> bool:
		var distance := (shape.global_position - global_position).length()
		var space_state := get_world_3d().direct_space_state
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = get_cone_radius(distance, angle / 2)
		var sphere_query := PhysicsShapeQueryParameters3D.new()
		sphere_query.shape = sphere_shape
		var forward := PhysicsUtil.get_forward(self)
		var sphere_origin := global_position + (forward * distance)
		sphere_query.transform.origin = sphere_origin
		sphere_query.collision_mask = collision_mask
		var intersect_info := space_state.intersect_shape(sphere_query)
		for info in intersect_info:
			var body : Node3D = info.collider
			var shape_index : int = info.shape
			var s := PhysicsUtil.get_collision_shape_in_body(body, shape_index)
			if shape == s:
				return true
		return false

	func _get_end_radius() -> float:
		return get_cone_radius(range, angle / 2)

	static func get_cone_radius(height: float, angle_deg: float) -> float:
		return height * tan(deg_to_rad(angle_deg))

	func _on_body_shape_entered(
		_body_rid: RID,
		body: Node3D,
		body_shape_index: int,
		_local_shape_index: int
	) -> void:
		var shape := PhysicsUtil.get_collision_shape_in_body(body, body_shape_index)
		_shapes_in_bounding_box.push_back(shape)
		_shape_body_map[shape] = body

	func _on_body_shape_exited(
		_body_rid: RID,
		body: Node3D,
		body_shape_index: int,
		local_shape_index: int
	) -> void:
		var shape := PhysicsUtil.get_collision_shape_in_body(body, body_shape_index)
		_shapes_in_bounding_box.erase(shape)
		_shape_body_map.erase(shape)
		if _shapes_in_cone.has(shape):
			_shapes_in_cone.erase(shape)
			shape_exited_cone.emit(shape)

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
	
	func probe(to: Vector3) -> ProbeResult:
		# Collide with bodies OR the environment
		var raycast_collision_mask := vision_cone.collision_mask | vision_cone.collision_environment_mask
		# can store reference to this?
		var space_state := vision_cone.get_world_3d().direct_space_state
		var from := vision_cone.global_position
		var query := PhysicsRayQueryParameters3D.create(
			from,
			to,
			raycast_collision_mask)
		var result := space_state.intersect_ray(query)
		return ProbeResult.new(from, to, result.collider if result.has("collider") else null)
	
	func _random_points_on_probe_mesh(count: int) -> Array[Vector3]:
		var surface_count := shape_probe_mesh.get_surface_count()
		var vertices = shape_probe_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var points : Array[Vector3] = []
		for point in count:
			points.push_back(vertices[_rng.randi_range(0, vertices.size() - 1)])
		return points
	
	func _get_scatter_points():
		var sample_points : Array[Vector3] = []
		var random_point_count := vision_cone.vision_test_shape_probe_count
		if !probe_results.is_empty():
			var last := probe_results[-1]
			if last.visible:
				sample_points.append(collision_shape.to_local(last.end))
				random_point_count -= 1
		sample_points.append_array(_random_points_on_probe_mesh(random_point_count))
		return sample_points
		
	func update():
		var body := collision_shape.get_parent()
		var sample_points : Array[Vector3] = []
		match vision_cone.vision_test_mode:
			VisionTestMode.SAMPLE_CENTER:
				sample_points = [Vector3.ZERO]
			VisionTestMode.SAMPLE_RANDOM_VERTICES: 
				sample_points = _get_scatter_points()

		probe_results = []
		visible = false
		for point in sample_points:
			var global_point := collision_shape.global_position + (collision_shape.global_basis * point)
			# TODO this check should happen in _get_scatter_points maybe?
			# ensure more points actually intersect objects midway through?
			# not sure it matters...
			# if !vision_cone._cone_area.point_within_angle(global_point):
			if !vision_cone._cone_area.point_within_cone(global_point):
				continue

			var probe_result := probe(global_point)
			probe_results.push_back(probe_result)

			# found body we were looking for
			if probe_result.collider == body:
				probe_result.visible = true
				visible = true
				return




	class ProbeResult:
		var start : Vector3
		var end : Vector3
		# var visible : bool
		var collider : Node3D
		var visible : bool = false

		func _init(
			start_: Vector3,
			end_: Vector3,
			collider_: Node3D
		):
			start = start_
			end = end_
			collider = collider_
			# visible = visible_

class VisionConeDebugVisualizer3D extends Node3D:

	const DEBUG_VISION_CONE_COLOR := Color(1, 1, 0, 0.005)
	const DEBUG_RAY_COLOR_IS_VISIBLE := Color(Color.GREEN, 1.0)
	const DEBUG_RAY_COLOR_IS_VISIBLE_TEST := Color(Color.GREEN, 0.1)
	const DEBUG_RAY_COLOR_IN_CONE := Color(Color.RED, 0.1)

	var vision_cone : VisionCone3D

	var _bounds_renderer : MeshInstance3D
	var _probe_renderer : DebugProbeLineRenderer

	func _init(vision_cone_: VisionCone3D):
		# attach
		vision_cone = vision_cone_
		vision_cone.shape_changed.connect(update_cone_shape)
		vision_cone.add_child(self, true, INTERNAL_MODE_BACK)

		# create cone renderer
		_bounds_renderer = MeshInstance3D.new()
		_bounds_renderer.mesh = CylinderMesh.new()
		_bounds_renderer.mesh.material = make_visualizer_material()
		add_child(_bounds_renderer, false, INTERNAL_MODE_BACK)

		_probe_renderer = DebugProbeLineRenderer.new()
		_probe_renderer.probe_data = vision_cone._shape_probe_data
		add_child(_probe_renderer)

	static func make_visualizer_material(albedo_color: Color = DEBUG_VISION_CONE_COLOR) -> StandardMaterial3D:
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
				VisionConeDebugVisualizer3D.DEBUG_RAY_COLOR_IS_VISIBLE)
			probe_failure_material = VisionConeDebugVisualizer3D.make_visualizer_material(
				VisionConeDebugVisualizer3D.DEBUG_RAY_COLOR_IN_CONE)


		func _process(_delta: float):
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