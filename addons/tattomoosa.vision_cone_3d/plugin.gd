@tool
extends EditorPlugin

const DEBUG_DRAW_TOOL := "Set Vision Cone Debug Draw Visibility"
var gizmo = preload("./src/editor/VisionCone3DGizmoPlugin.gd").new()

func _enter_tree():
	gizmo.editor_interface = get_editor_interface()
	gizmo.undo_redo = get_undo_redo()
	add_node_3d_gizmo_plugin(gizmo)

	# add_tool_menu_item(
	# 	DEBUG_DRAW_TOOL,
	# 	func():
	# 		VisionCone3D.debug_draw_all = !VisionCone3D.debug_draw_all
	# )


func _exit_tree():
	remove_node_3d_gizmo_plugin(gizmo)
	# remove_tool_menu_item(DEBUG_DRAW_TOOL)
