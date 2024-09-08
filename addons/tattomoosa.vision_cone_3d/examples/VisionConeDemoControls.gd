extends PanelContainer

@export var vision_cone : VisionCone3D

@onready var raycast_center_checkbox : CheckBox = %RaycastCenterCheckBox
@onready var raycast_scatter_checkbox : CheckBox = %RaycastScatterCheckBox
@onready var raycast_count_slider : Slider = %RaycastsPerFrameSlider
@onready var angle_slider : Slider = %AngleSlider
@onready var range_slider : Slider = %RangeSlider
@onready var rotation_slider : Slider = %ObserverRotationSlider

func _ready():
	raycast_center_checkbox.toggled.connect(_set_center)
	raycast_scatter_checkbox.toggled.connect(_set_scatter)
	raycast_count_slider.value_changed.connect(func(value: float): vision_cone.vision_test_shape_probe_count = value)
	angle_slider.value_changed.connect(func(value: float): vision_cone.angle = value)
	range_slider.value_changed.connect(func(value: float): vision_cone.range = value)
	rotation_slider.value_changed.connect(func(value: float): vision_cone.rotation_degrees.y = value)

	vision_cone.vision_test_shape_probe_count = raycast_count_slider.value
	vision_cone.angle = angle_slider.value
	vision_cone.range = range_slider.value
	vision_cone.rotation_degrees.y = rotation_slider.value
	_set_center(raycast_center_checkbox.button_pressed)
	_set_scatter(raycast_scatter_checkbox.button_pressed)

func _set_center(value: bool):
	if !value:
		return
	vision_cone.vision_test_mode = VisionCone3D.VisionTestMode.SAMPLE_CENTER

func _set_scatter(value: bool):
	if !value:
		return
	vision_cone.vision_test_mode = VisionCone3D.VisionTestMode.SAMPLE_RANDOM_VERTICES