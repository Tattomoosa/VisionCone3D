extends Node3D

const ProbeResult := VisionCone3D.VisionTestProber.ProbeResult

# TODO should be modifiable via EditorSettings
const DEBUG_VISION_CONE_COLOR := Color(1, 1, 0, 0.02)
# TODO should be modifiable via EditorSettings
const DEBUG_RAY_COLOR_IS_VISIBLE := Color(Color.GREEN, 0.8)
# TODO should be modifiable via EditorSettings
const DEBUG_RAY_COLOR_IS_OBSTRUCTED := Color(Color.RED, 0.4)

@export var vision_cone : VisionCone3D

var debug_vision_cone_color := DEBUG_VISION_CONE_COLOR
var debug_ray_color_is_visible := DEBUG_RAY_COLOR_IS_VISIBLE
var debug_ray_color_in_cone := DEBUG_RAY_COLOR_IS_OBSTRUCTED


var _bounds_renderer : MeshInstance3D
var _probe_renderer : DebugProbeLineRenderer

func _init() -> void:
	# create cone renderer
	_bounds_renderer = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.material = make_visualizer_material()
	_bounds_renderer.mesh = mesh
	add_child(_bounds_renderer, false, INTERNAL_MODE_BACK)

	_probe_renderer = DebugProbeLineRenderer.new()
	_probe_renderer.probe_success_material = make_visualizer_material(debug_ray_color_is_visible)
	_probe_renderer.probe_failure_material = make_visualizer_material(debug_ray_color_in_cone)
	add_child(_probe_renderer)

@warning_ignore("return_value_discarded")
func _ready() -> void:
	vision_cone = get_parent()
	_probe_renderer.body_probe_data = vision_cone._body_probe_data
	vision_cone.shape_changed.connect(update_cone_shape)
	update_cone_shape()

func make_visualizer_material(albedo_color: Color = debug_vision_cone_color) -> StandardMaterial3D:
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
	var body_probe_data: Dictionary
	var probe_success_material : StandardMaterial3D
	var probe_failure_material : StandardMaterial3D

	func _init() -> void:
		mesh = ImmediateMesh.new()

	func _process(_delta: float) -> void:
		if Engine.is_editor_hint():
			return
		(mesh as ImmediateMesh).clear_surfaces()
		if body_probe_data.is_empty():
			return
		var successful : Array[ProbeResult] = []
		var failed : Array[ProbeResult] = []

		for prober_list : Array[VisionCone3D.VisionTestProber] in body_probe_data.values():
			for prober in prober_list:
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

	func _add_probe_lines_surface(probes: Array[ProbeResult]) -> void:
		var imesh := mesh as ImmediateMesh
		imesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for probe in probes:
			imesh.surface_add_vertex(to_local(probe.start))
			imesh.surface_add_vertex(to_local(probe.end))
		imesh.surface_end()
