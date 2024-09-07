extends PanelContainer

@export var vision_cone : VisionCone3D

@onready var raycast_center_checkbox : CheckBox = %RaycastCenterCheckBox
@onready var raycast_scatter_checkbox : CheckBox = %RaycastScatterCheckBox
@onready var raycast_count_slider : Slider = %RaycastsPerFrameSlider

func _ready():
	raycast_center_checkbox.toggled.connect(_set_center)
	raycast_scatter_checkbox.toggled.connect(_set_scatter)
	raycast_count_slider.value_changed.connect(
		func(value: float):
			vision_cone.vision_test_max_raycast_per_frame = value
	)
	_set_center(raycast_center_checkbox.button_pressed)
	_set_center(raycast_scatter_checkbox.button_pressed)

func _set_center(value: bool):
	if !value:
		return

	vision_cone.vision_test_mode = VisionCone3D.VisionTestMode.SAMPLE_CENTER
	raycast_count_slider.value = 1
	raycast_count_slider.editable = false

func _set_scatter(value: bool):
	if !value:
		return

	vision_cone.vision_test_mode = VisionCone3D.VisionTestMode.SAMPLE_RANDOM_VERTICES
	raycast_count_slider.editable = true