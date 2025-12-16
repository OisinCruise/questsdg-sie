extends RigidBody3D
## Pump handle that pivots in place using physics constraints
## Uses RigidBody3D with HingeJoint3D for proper VR interaction

signal pump_cycle_completed

# Rotation limits (in degrees for joint)
@export var min_angle_deg: float = -35.0  # Maximum downward rotation
@export var max_angle_deg: float = 5.0    # Rest position
@export var pump_threshold_deg: float = -25.0  # Angle at which pump triggers

var is_being_pumped: bool = false
var scene_root: Node3D = null
var hinge_joint: HingeJoint3D = null
var pivot_body: StaticBody3D = null
var is_enabled: bool = false

func _ready() -> void:
	# Configure RigidBody3D for constrained movement
	gravity_scale = 0.5  # Light gravity to return handle up
	mass = 0.3
	linear_damp = 2.0
	angular_damp = 3.0
	freeze = true  # Start frozen

	# Set collision layers (layer 2 for grabbables)
	collision_layer = 2
	collision_mask = 1

	_find_scene_root()
	_setup_hinge_constraint()
	_setup_hand_detection()

func _find_scene_root() -> void:
	var current = get_parent()
	while current:
		if current.has_method("_on_pump_cycle"):
			scene_root = current
			print("PumpHandle: Found scene root: ", current.name)
			break
		current = current.get_parent()

	if not scene_root:
		push_warning("PumpHandle: Could not find scene with _on_pump_cycle method")

func _setup_hinge_constraint() -> void:
	# Create invisible static body as pivot anchor
	pivot_body = StaticBody3D.new()
	pivot_body.name = "PumpPivot"
	get_parent().add_child(pivot_body)
	pivot_body.global_position = global_position

	# Create HingeJoint3D to constrain rotation
	hinge_joint = HingeJoint3D.new()
	hinge_joint.name = "PumpHinge"
	hinge_joint.node_a = pivot_body.get_path()
	hinge_joint.node_b = get_path()

	# Enable angle limits
	hinge_joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	hinge_joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(min_angle_deg))
	hinge_joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(max_angle_deg))

	# Add some softness and bias for smooth movement
	hinge_joint.set_param(HingeJoint3D.PARAM_LIMIT_SOFTNESS, 0.9)
	hinge_joint.set_param(HingeJoint3D.PARAM_LIMIT_RELAXATION, 1.0)

	get_parent().add_child(hinge_joint)
	print("PumpHandle: Created hinge constraint")

func _setup_hand_detection() -> void:
	# Find existing HandDetectArea or create one
	var hand_detect_area: Area3D = null

	if has_node("HandDetectArea"):
		hand_detect_area = $HandDetectArea
	else:
		hand_detect_area = Area3D.new()
		hand_detect_area.name = "HandDetectArea"
		hand_detect_area.collision_layer = 0
		hand_detect_area.collision_mask = 1  # Detect hands on layer 1
		hand_detect_area.monitoring = true
		hand_detect_area.monitorable = true

		var shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(0.3, 0.2, 0.2)
		shape.shape = box
		shape.position = Vector3(0.15, 0, 0)
		hand_detect_area.add_child(shape)
		add_child(hand_detect_area)

	# Connect to hand proximity detection
	if not hand_detect_area.area_entered.is_connected(_on_hand_area_entered):
		hand_detect_area.area_entered.connect(_on_hand_area_entered)
	if not hand_detect_area.area_exited.is_connected(_on_hand_area_exited):
		hand_detect_area.area_exited.connect(_on_hand_area_exited)

func _on_hand_area_entered(area: Area3D) -> void:
	# Register this pump handle as grabbable with the hand
	var hand = area.get_parent()
	if hand and hand.has_method("register_nearby_grabbable"):
		hand.register_nearby_grabbable(self)
		print("PumpHandle: Registered with hand - ", hand.name)

func _on_hand_area_exited(area: Area3D) -> void:
	var hand = area.get_parent()
	if hand and hand.has_method("unregister_nearby_grabbable"):
		hand.unregister_nearby_grabbable(self)

func _physics_process(_delta: float) -> void:
	if not is_enabled:
		return

	# Check rotation for pump trigger
	var current_angle_deg = rad_to_deg(rotation.x)

	if current_angle_deg <= pump_threshold_deg:
		if not is_being_pumped:
			is_being_pumped = true
			_trigger_pump_cycle()
	elif current_angle_deg >= pump_threshold_deg + 10:
		is_being_pumped = false

func _trigger_pump_cycle() -> void:
	emit_signal("pump_cycle_completed")
	print("PumpHandle: Pump cycle triggered!")

	if scene_root and scene_root.has_method("_on_pump_cycle"):
		scene_root._on_pump_cycle()

func enable() -> void:
	is_enabled = true
	freeze = false
	print("PumpHandle: Enabled")

func disable() -> void:
	is_enabled = false
	freeze = true
	print("PumpHandle: Disabled")

# Called when grabbed - apply downward force or let physics handle it
func on_grabbed(_hand: Node3D = null) -> void:
	pass  # Physics handles movement via hand tracking

func on_released() -> void:
	pass  # Physics handles return via gravity
