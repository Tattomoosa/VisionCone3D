@tool
@icon("../icons/VisionCone3D.svg")
class_name VisionCone3D
extends Node3D

## Simulates a cone vision shape and also checks to make sure
## object is unobstructed

# static var debug_draw_all := false

#region signals
signal body_visible(body: Node3D)
signal body_hidden(body: Node3D)
#endregion signals

#region export_variables

## Distance that can be seen (the height of the vision cone)
@warning_ignore("shadowed_global_identifier")
@export var range := 20.0:
	set(v):
		range = v
		_update_shape()
## Angle of the vision cone
@export var angle := 45.0:
	set(v):
		angle = v
		_update_shape()
## Whether or not to draw debug information
@export var debug_draw := false:
	set(v):
		debug_draw = v
		_draw_bounds()
		if !v:
			for shape in _shapes_in_bounding_box:
				Debug.delete_line(str(self) + ":" + str(shape))

@export_group("Collision", "collision_")

## Collision layer of the vision cone
@export_flags_3d_physics var collision_layer : int = 1:
	set(value):
		collision_layer = value
		if is_node_ready():
			_area.collision_layer = collision_layer

## Collision mask of the vision cone (Tracked and considered "visible")
## 
## Generally useful for characters
@export_flags_3d_physics var collision_mask : int = 1:
	set(value):
		collision_mask = value
		if is_node_ready():
			_area.collision_mask = collision_mask

## Collision mask of what objects can obscure visible objects (but don't need to
## be tracked as visible)
## 
## Generally useful for the environment
@export_flags_3d_physics var collision_environment_mask : int = 1

#endregion export_variables

#region public_variables
var end_radius: float:
	get: return _end_radius

# var bodies_visible: Array[Node3D]:
# 	get:
		# return _bodies_visible.duplicate()
#endregion public_variables

#region private_variables

var _shape : BoxShape3D
var _collision_shape : CollisionShape3D
var _area : Area3D

# var _bodies_visible : Array[Node3D] = []
# var _bodies_inside : Array[Node3D] = []

var _shapes_visible : Array[Node3D] = []
var _shapes_in_bounding_box : Array[Node3D] = []

var _bounds_renderer : MeshInstance3D
var _end_radius: float = 0.0
#endregion private_variables

#region constants
const DEBUG_VISION_CONE_COLOR := Color(1, 1, 0, 0.02)
const DEBUG_RAY_COLOR_IS_VISIBLE := Color(Color.GREEN, 1.0)
const DEBUG_RAY_COLOR_IN_CONE := Color(Color.RED, 1.0)
const DEBUG_RAY_COLOR_IN_BOUNDING_BOX := Color(Color.WHITE, 0.01)
#endregion constants

#region engine_callbacks
func _init() -> void:
	_area = Area3D.new()
	_area.collision_layer = collision_layer
	_area.collision_mask = collision_mask
	add_child(_area)
	_collision_shape = CollisionShape3D.new()
	_area.add_child(_collision_shape)
	_shape = BoxShape3D.new()
	_collision_shape.shape = _shape

	# debug
	_bounds_renderer = MeshInstance3D.new()
	_bounds_renderer.mesh = CylinderMesh.new()
	_bounds_renderer.mesh.material = _cone_visualizer_material()
	add_child(_bounds_renderer, false, INTERNAL_MODE_BACK)

	_update_shape()

	# TODO - maintain a list of shapes to check for body visibility
	_area.body_shape_entered.connect(_on_body_shape_entered)
	_area.body_shape_exited.connect(_on_body_shape_exited)

	Debug.toggle_button(
		"Show Vision Cones",
		func(value: bool) -> void:
			debug_draw = value
	)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	for shape in _shapes_in_bounding_box:
		_update_shape_visibility(shape)
#endregion engine_callbacks

#region public_methods
func point_in_vision_cone(global_point: Vector3) -> bool:
	var body_pos := -global_basis.z
	var pos := global_point - global_position
	var angle_to := pos.angle_to(body_pos)
	var angle_deg := rad_to_deg(angle_to)
	return angle_deg <= angle

func shape_in_vision_cone(shape: Node3D) -> bool:
	var distance := (shape.global_position - global_position).length()
	var space_state := get_world_3d().direct_space_state
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = get_cone_radius(distance, angle)
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
#endregion public_methods

#region private_methods
func _get_body_center_position(body: Node3D) -> Vector3:
	# TODO get bounds, find center, return
	if body is PhysicsBody3D:
		print("body is physicsbody: ", body)
	elif body is CollisionShape3D:
		print("body is collisionshape: ", body)
	else:
		push_warning("NO HANDLEABLE BODY FOUND")
	return Vector3.ZERO

func _update_shape_visibility(shape: Node3D) -> void:
	# TODO shape can also be CollisionPolygon3D
	# need to determine if that needs separate handling...
	if shape is CollisionShape3D:
		var s := shape as CollisionShape3D
		# TODO i think this always works?
		var body := shape.get_parent()

		# not in cone
		if !shape_in_vision_cone(shape):
			# if debug_draw: Debug.draw_line(global_position, shape.global_position, DEBUG_RAY_COLOR_IN_BOUNDING_BOX, str(self) + ":" + str(shape))
			if debug_draw: Debug.delete_line(str(self) + ":" + str(shape))
			if _shapes_visible.has(shape):
				_shapes_visible.erase(shape)
			return

		# obstructed
		var result := _raycast_collision(s.global_position)
		if result != body:
			if _shapes_visible.has(shape):
				_shapes_visible.erase(shape)
				if debug_draw:
					Debug.draw_line(global_position, shape.global_position, DEBUG_RAY_COLOR_IN_CONE, str(self) + ":" + str(shape))
				return

		# visible
		if !_shapes_visible.has(shape):
			_shapes_visible.push_back(shape)
		if debug_draw:
			Debug.draw_line(global_position, shape.global_position, DEBUG_RAY_COLOR_IS_VISIBLE, str(self) + ":" + str(shape))
		return

func _draw_bounds() -> void:
	var m : CylinderMesh = _bounds_renderer.mesh
	# TODO free/add meshinstance when toggled
	if !debug_draw:
		m.bottom_radius = 0
		m.height = 0
		_bounds_renderer.hide()
		return

	_bounds_renderer.show()
	# _end_radius = _get_cone_end_radius()
	m.top_radius = 0
	m.bottom_radius = end_radius
	m.height = range
	_bounds_renderer.rotation_degrees = Vector3(90, 0, 0)
	_bounds_renderer.position.z = -range / 2

func _update_shape() -> void:
	update_gizmos()
	notify_property_list_changed()
	_end_radius = _get_cone_end_radius()
	var end_diameter := end_radius * 2
	_shape.size = Vector3(end_diameter, end_diameter, range)
	_collision_shape.position.z = -range / 2
	_draw_bounds()

func _on_body_shape_entered(
	_body_rid: RID,
	body: Node3D,
	body_shape_index: int,
	_local_index: int
) -> void:
	var body_shape_node := PhysicsUtil.get_collision_shape_in_body(body, body_shape_index)
	_shapes_in_bounding_box.push_back(body_shape_node)

func _on_body_shape_exited(
	_body_rid: RID,
	body: Node3D,
	body_shape_index: int,
	_local_index: int
) -> void:
	var body_shape_node := PhysicsUtil.get_collision_shape_in_body(body, body_shape_index)
	_shapes_in_bounding_box.erase(body_shape_node)
	if debug_draw:
		Debug.delete_line(str(self) + ":" + str(body_shape_node))

func _raycast_collision(world_pos: Vector3) -> Node3D:
	# Collide with bodies OR the environment
	var raycast_collision_mask := collision_mask | collision_environment_mask
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, world_pos, raycast_collision_mask)
	var result := space_state.intersect_ray(query)
	if !result.has("collider"):
		return null
	else:
		return result.collider

func _get_cone_end_radius() -> float:
	return get_cone_radius(range, angle)
#endregion private_methods

#region static_methods
static func _cone_visualizer_material(albedo_color: Color = DEBUG_VISION_CONE_COLOR) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo_color
	# mat.emission_enabled = true
	# mat.emission = albedo_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

static func get_cone_radius(height: float, angle_deg: float) -> float:
	return height * tan(deg_to_rad(angle_deg))
#endregion

# #region DEPRECATED

# # deprecated
# func collider_in_vision_cone(collider: Node3D) -> bool:
# 	# var distance := (global_position - collider.position).length()
# 	var distance := (collider.global_position - global_position).length()
# 	var space_state := get_world_3d().direct_space_state
# 	var sphere_shape := SphereShape3D.new()
# 	sphere_shape.radius = get_cone_radius(distance, angle)
# 	var sphere_query := PhysicsShapeQueryParameters3D.new()
# 	sphere_query.shape = sphere_shape
# 	var forward := PhysicsUtil.get_forward(self)
# 	var sphere_origin := global_position + (forward * distance)
# 	sphere_query.transform.origin = sphere_origin
# 	var intersect_info := space_state.intersect_shape(sphere_query)
# 	for info in intersect_info:
# 		if collider == info.collider:
# 			return true
# 	return false

# # deprecated
# func _on_body_entered(body: Node3D) -> void:
# 	_bodies_inside.push_back(body)

# # deprecated
# func _on_body_exited(body: Node3D) -> void:
# 	_bodies_inside.erase(body)
# 	if debug_draw:
# 		Debug.delete_line(str(self) + ":" + str(body))

# # deprecated
# func _update_body_visibility(body: Node3D) -> void:
# 	var result := _raycast_collision(body.global_position)
# 	if result == body:
# 		var debug_draw_color := Color()
# 		if collider_in_vision_cone(body):
# 			debug_draw_color = Color.GREEN

# 			if !_bodies_visible.has(body):
# 				_bodies_visible.push_back(body)
# 				body_visible.emit(body)

# 		else:
# 			debug_draw_color = Color(1, 1, 1, 0.1)
# 			if _bodies_visible.has(body):
# 				_bodies_visible.erase(body)
# 				body_hidden.emit(body)

# 		if debug_draw:
# 			Debug.draw_line(global_position, body.global_position, debug_draw_color, str(self) + ":" + str(body))

# 	else:
# 		if _bodies_visible.has(body):
# 			_bodies_visible.erase(body)
# 			body_hidden.emit(body)

# 			if debug_draw:
# 				Debug.delete_line(str(self) + ":" + str(body))

# #endregion