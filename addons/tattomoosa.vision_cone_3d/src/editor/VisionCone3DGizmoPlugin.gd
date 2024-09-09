extends EditorNode3DGizmoPlugin

var texture = preload("../../icons/GizmoVisionCone.svg")
var editor_interface : EditorInterface
var undo_redo: EditorUndoRedoManager

var _start_drag_mouse_world_position : Vector3
var _start_drag_range: float
var _start_drag_angle : float

func _init():
	create_material("cone_preview", Color(1, 1, 0), false)
	create_handle_material("handles")
	create_icon_material(
		"icon",
		texture,
	)

func _get_gizmo_name():
	return "VisionCone3D"

func _get_handle_name(
	gizmo: EditorNode3DGizmo,
	handle_id: int,
	secondary: bool
):
	match handle_id:
		0: return "Range"
		1: return "Angle"

func _get_handle_value(
	gizmo: EditorNode3DGizmo,
	handle_id: int,
	secondary: bool
):
	var vc : VisionCone3D = gizmo.get_node_3d()
	match handle_id:
		0: return vc.range
		1: return vc.angle

func _begin_handle_action(
	gizmo: EditorNode3DGizmo,
	handle_id,
	secondary
) -> void:
	var vc : VisionCone3D = gizmo.get_node_3d()
	_start_drag_mouse_world_position = vc.global_position + (-vc.global_basis.z * vc.range)
	match handle_id:
		0: # range
			_start_drag_range = vc.range
		1: # angle
			_start_drag_angle = vc.angle

func _commit_handle(gizmo, handle_id, secondary, restore, cancel):
	var vc : VisionCone3D = gizmo.get_node_3d()
	match handle_id:
		0: # range
			undo_redo.create_action("Set range")
			undo_redo.add_do_property(vc, "range", vc.range)
			undo_redo.add_undo_property(vc, "range", _start_drag_range)
		1: # angle
			undo_redo.create_action("Set angle")
			undo_redo.add_do_property(vc, "angle", vc.angle)
			undo_redo.add_undo_property(vc, "angle", _start_drag_angle)
	undo_redo.commit_action()

func _set_handle(
	gizmo: EditorNode3DGizmo,
	handle_id: int,
	secondary: bool,
	camera: Camera3D,
	screen_pos: Vector2
):
	var vc : VisionCone3D = gizmo.get_node_3d()
	match handle_id:
		0: # range
			# TODO this mostly works but not if camera.y is near vc.y
			var world_pos := _calculate_mouse_world_position(
				camera,
				vc.global_position.y,
				Vector3.UP
			)
			var local_pos := vc.to_local(world_pos)
			var new_range = -local_pos.z
			if new_range > 0:
				vc.range = new_range

		1: # angle
			var local_end_range_pos := Vector3(0, 0, -vc.range)

			# TODO this mostly works but not if camera.y is near vc.y
			var world_pos := _calculate_mouse_world_position(
				camera,
				vc.global_position.y,
				Vector3.UP
			)
			var local_pos := vc.to_local(world_pos)
			var radius := local_pos.x
			vc.angle = abs(rad_to_deg(atan(radius / vc.range))) * 2
	gizmo.get_node_3d().update_gizmos()

func _has_gizmo(node: Node3D):
	return node is VisionCone3D

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var vc : VisionCone3D = gizmo.get_node_3d()

	gizmo.add_unscaled_billboard(get_material("icon", gizmo), 0.04)

	var lines = _make_cone_lines(360, 6, vc.end_radius, vc.range)
	var cylinder_mesh := CylinderMesh.new()

	var handles = PackedVector3Array([
		Vector3(0, 0, -vc.range),
		Vector3(vc.end_radius, 0, -vc.range)
	])

	#var cone_preview_material := "cone_preview_selected" if editor_interface.get_selection().get_selected_nodes().has(vc) else "cone_preview_unselected"

	# Show cone when unselected, kind of distracting...
	# var cone_alpha := 1.0 if editor_interface.get_selection().get_selected_nodes().has(vc) else 0.0
	var cone_alpha := 1.0

	if editor_interface.get_selection().get_selected_nodes().has(vc):
		gizmo.add_lines(lines, get_material("cone_preview", gizmo), false, Color(1, 1, 1, cone_alpha))
	gizmo.add_handles(handles, get_material("handles", gizmo), [])

func _make_cone_lines(
	resolution: int,
	support_resolution: int,
	end_radius: float,
	range: float
):
	var points: PackedVector3Array = []
	var support_every := resolution / support_resolution
	var start : Vector3
	for i in resolution:
		# circle logic
		var angle := float(i) * TAU / resolution 
		var x := cos(angle) * end_radius
		var y := sin(angle) * end_radius
		var point := Vector3(x, y, -range)
		points.append(point)

		if i % support_every == 0:
			points.append(Vector3.ZERO)
			points.append(point)

		if i == 0:
			start = point
		else:
			points.append(point)
	points.append(start)
	points.append(Vector3.ZERO)
	points.append(Vector3(0, 0, -range))
	return points

static func _calculate_mouse_world_position(
	camera: Camera3D,
	# world position along plane normal, could use a better name
	intersection_point: float,
	plane_normal: Vector3 = Vector3.UP
) -> Vector3:
	var position := camera.get_viewport().get_mouse_position()
	var camera_from := camera.project_ray_origin(position)
	var camera_to := camera.project_ray_normal(position)

	var n := plane_normal # plane normal
	var p := camera_from # ray origin
	var v := camera_to # ray direction
	var d := intersection_point # distance of the plane from origin
	var t := -(n.dot(p) - d) / n.dot(v) # solving for plain/ray intersection

	return p + t * v