class_name XRGrabbable
extends RigidBody3D

signal grabbed(hand: XRPinchHand)
signal released(hand: XRPinchHand)
signal placed_in_target(target: Node3D)

@export var grab_distance: float = 0.5  # Increased for better XR grabbing
@export var highlight_material: Material = null
@export var grab_smoothing: float = 15.0  # Higher = faster following, lower = smoother

var is_grabbed: bool = false
var grabbing_hand: XRPinchHand = null
var original_parent: Node = null
var original_freeze: bool = false

func _ready() -> void:
	original_freeze = freeze
	add_to_group("grabbable")
	_setup_detection_area()

func _setup_detection_area() -> void:
	var area: Area3D
	if has_node("GrabArea"):
		area = $GrabArea
		# Update collision settings
		area.collision_layer = 0
		area.collision_mask = 1
	else:
		area = Area3D.new()
		area.name = "GrabArea"
		area.collision_layer = 0
		area.collision_mask = 1
		var shape = CollisionShape3D.new()
		var sphere = SphereShape3D.new()
		sphere.radius = grab_distance
		shape.shape = sphere
		area.add_child(shape)
		add_child(area)

	# Connect signals if not already connected
	if not area.area_entered.is_connected(_on_grab_area_entered):
		area.area_entered.connect(_on_grab_area_entered)
	if not area.area_exited.is_connected(_on_grab_area_exited):
		area.area_exited.connect(_on_grab_area_exited)

func _on_grab_area_entered(area: Area3D) -> void:
	if area.name.contains("hand"):
		var potential_hand = area.get_parent()
		if potential_hand is XRPinchHand:
			potential_hand.register_nearby_grabbable(self)

func _on_grab_area_exited(area: Area3D) -> void:
	if area.name.contains("hand"):
		var potential_hand = area.get_parent()
		if potential_hand is XRPinchHand:
			potential_hand.unregister_nearby_grabbable(self)

func _physics_process(delta: float) -> void:
	if is_grabbed and grabbing_hand:
		global_position = global_position.lerp(grabbing_hand.global_position, grab_smoothing * delta)

func try_grab(hand: XRPinchHand) -> bool:
	if is_grabbed:
		return false

	if not hand.pinching:
		return false

	var distance = global_position.distance_to(hand.global_position)
	if distance > grab_distance:
		return false

	_do_grab(hand)
	return true

func _do_grab(hand: XRPinchHand) -> void:
	is_grabbed = true
	grabbing_hand = hand
	original_freeze = freeze
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	if highlight_material:
		_apply_highlight(false)

	emit_signal("grabbed", hand)

func release() -> void:
	if not is_grabbed:
		return

	var released_hand = grabbing_hand
	is_grabbed = false
	grabbing_hand = null
	freeze = original_freeze

	emit_signal("released", released_hand)

func force_release() -> void:
	release()

func _apply_highlight(highlighted: bool) -> void:
	if not highlight_material:
		return
	pass

func on_placed_in_target(target: Node3D) -> void:
	emit_signal("placed_in_target", target)
