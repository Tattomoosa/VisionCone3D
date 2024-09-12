extends PanelContainer

@export var vision_cone : VisionCone3D
@export var cameras : Array[Camera3D] = []

@onready var vision_test_center_checkbox : CheckBox = %VisionTestCenterCheckBox
@onready var vision_test_scatter_checkbox : CheckBox = %VisionTestScatterCheckBox
@onready var raycast_count_slider : Slider = %RaycastsPerFrameSlider
@onready var angle_slider : Slider = %AngleSlider
@onready var range_slider : Slider = %RangeSlider
@onready var rotation_slider : Slider = %ObserverRotationSlider
@onready var position_slider : Slider = %ObserverPositionSlider
@onready var max_bodies_slider : Slider = %MaxBodiesSlider
@onready var switch_camera_button : Button = %SwitchCameraButton

func _ready():
	vision_test_center_checkbox.toggled.connect(_set_center)
	vision_test_scatter_checkbox.toggled.connect(_set_scatter)
	raycast_count_slider.value_changed.connect(func(value: float): vision_cone.vision_test_shape_max_probe_count = value)
	angle_slider.value_changed.connect(func(value: float): vision_cone.angle = value)
	range_slider.value_changed.connect(func(value: float): vision_cone.range = value)
	rotation_slider.value_changed.connect(func(value: float): vision_cone.get_parent().rotation_degrees.y = -value)
	position_slider.value_changed.connect(func(value: float): vision_cone.get_parent().position.x = value)
	max_bodies_slider.value_changed.connect(func(value: float): vision_cone.vision_test_max_body_count = value)
	if cameras.is_empty():
		switch_camera_button.hide()
	else:
		cameras[0].current = true
		switch_camera_button.text = "Current Camera: " + cameras[0].name
		switch_camera_button.pressed.connect(
			func():
				for i in cameras.size():
					var cam := cameras[i]
					if cam.current:
						cam.current = false
						var next_cam : Camera3D
						if (i + 1) < cameras.size():
							next_cam = cameras[i + 1]
						else:
							next_cam = cameras[0]
						next_cam.current = true
						switch_camera_button.text = "Current Camera: " + next_cam.name
						return
		)

	angle_slider.value = vision_cone.angle 
	range_slider.value = vision_cone.range 
	max_bodies_slider.value = vision_cone.vision_test_max_body_count
	raycast_count_slider.value = vision_cone.vision_test_shape_max_probe_count 

	if vision_cone.get_parent() is CharacterBody3D:
		vision_cone.get_parent().rotation_degrees.y = -rotation_slider.value
		vision_cone.get_parent().position.x = position_slider.value
	else:
		rotation_slider.get_parent().hide()
		position_slider.get_parent().hide()

	_set_center(vision_test_center_checkbox.button_pressed)
	_set_scatter(vision_test_scatter_checkbox.button_pressed)

	size.y = 0

func _set_center(value: bool):
	if !value:
		return
	vision_cone.vision_test_mode = VisionCone3D.VisionTestMode.SAMPLE_CENTER

func _set_scatter(value: bool):
	if !value:
		return
	vision_cone.vision_test_mode = VisionCone3D.VisionTestMode.SAMPLE_RANDOM_VERTICES