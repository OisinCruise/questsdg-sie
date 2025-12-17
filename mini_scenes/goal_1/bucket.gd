extends XRGrabbable
class_name Bucket
## What: Grabbable bucket that fills with water over time
## Who: XRGrabbable parent, goal_1_scene water detection
## Why: Goal 1 poverty simulation - collect water for community

signal filled

@export var fill_threshold: float = 1.5  # sec to fill
var fill_amount: float = 0.0
var is_filled: bool = false
var fill_indicator: MeshInstance3D = null

func _ready() -> void:
	grab_distance = 0.4
	super._ready()
	
	if has_node("FillIndicator"):
		fill_indicator = $FillIndicator
		fill_indicator.visible = false

func add_water(delta: float) -> void:
	if is_filled:
		return
	
	fill_amount += delta
	_update_fill_visual()
	
	if fill_amount >= fill_threshold:
		_complete_fill()

func _update_fill_visual() -> void:
	if not fill_indicator:
		return
	
	var fill_percent = clamp(fill_amount / fill_threshold, 0.0, 1.0)
	
	if fill_percent > 0.1 and not fill_indicator.visible:
		fill_indicator.visible = true
	
	# Visual: Y-scale for water level
	fill_indicator.scale.y = max(0.01, fill_percent)
	fill_indicator.position.y = -0.1 + (fill_percent * 0.1)

func _complete_fill() -> void:
	is_filled = true
	if fill_indicator:
		fill_indicator.visible = true
		fill_indicator.scale.y = 1.0
		fill_indicator.position.y = 0.0
	emit_signal("filled")

func reset() -> void:
	fill_amount = 0.0
	is_filled = false
	if fill_indicator:
		fill_indicator.visible = false
		fill_indicator.scale.y = 0.01
		fill_indicator.position.y = -0.1
