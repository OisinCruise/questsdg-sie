extends RigidBody3D

var original_position: Vector3
var min_y: float = -0.2  # Minimum Y offset for pump down
var max_y: float = 0.3   # Maximum Y offset for pump up
var is_being_pumped: bool = false

func _ready() -> void:
	original_position = position
	freeze = true  # Start frozen

func _physics_process(_delta: float) -> void:
	if freeze:
		return
	
	# Constrain handle movement to vertical axis
	var current_pos = position
	current_pos.x = original_position.x
	current_pos.z = original_position.z
	
	# Clamp Y position
	current_pos.y = clamp(current_pos.y, original_position.y + min_y, original_position.y + max_y)
	
	position = current_pos
	
	# Detect pump cycle (down then up)
	if current_pos.y <= original_position.y + min_y + 0.1:
		if not is_being_pumped:
			is_being_pumped = true
			# Emit signal for water generation
			get_parent().get_parent()._on_pump_cycle()  # Call parent scene method
	elif current_pos.y >= original_position.y + max_y - 0.1:
		is_being_pumped = false
