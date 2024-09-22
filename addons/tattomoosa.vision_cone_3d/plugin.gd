@tool
extends EditorPlugin

const DEBUG_DRAW_TOOL := "Set Vision Cone Debug Draw Visibility"
const VisionCone3DGizmoPlugin := preload ("./src/editor/VisionCone3DGizmoPlugin.gd")
var gizmo : VisionCone3DGizmoPlugin = VisionCone3DGizmoPlugin.new()

func _enter_tree() -> void:
	gizmo.undo_redo = get_undo_redo()
	add_node_3d_gizmo_plugin(gizmo)

	# add_tool_menu_item(
	# 	DEBUG_DRAW_TOOL,
	# 	func():
	# 		VisionCone3D.debug_draw_all = !VisionCone3D.debug_draw_all
	# )


func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(gizmo)
	# remove_tool_menu_item(DEBUG_DRAW_TOOL)
