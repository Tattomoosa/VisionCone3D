extends Label

@export var range_control : Range

func _ready():
	range_control.value_changed.connect(_set_displayed_value)
	_set_displayed_value(range_control.value)

func _set_displayed_value(_value: float):
	text = str(_value)