class_name XRPinchHand

extends XRNode3D

signal pinch_started
signal pinch_ended
signal object_released(object: RigidBody3D)

@export var selected = false
@export var pinching = false

var held_object: RigidBody3D = null
var nearby_grabbables: Array[Node3D] = []

@export var grab_smoothing: float = 15.0  # Higher = faster following, lower = smoother

# Stored state for held object
var _held_original_freeze: bool = false
var _held_original_gravity: float = 1.0
var _held_original_layer: int = 0
var _held_original_mask: int = 0

func _ready() -> void:
	$HandPoseDetector.connect("pose_started", _on_hand_pose_detector_pose_started)
	$HandPoseDetector.connect("pose_ended", _on_hand_pose_detector_pose_ended)

func _physics_process(delta: float) -> void:
	_check_for_grab()

	# Move held object to hand position with smoothing
	if held_object and is_instance_valid(held_object):
		held_object.global_position = held_object.global_position.lerp(global_position, grab_smoothing * delta)


func _on_hand_pose_detector_pose_started(p_name: String) -> void:
	print(p_name + " started")
	if p_name == "ThumbsUp":
		selected = true
	if p_name == "Index Pinch":
		pinching = true
		emit_signal("pinch_started")


func _on_hand_pose_detector_pose_ended(p_name: String) -> void:
	print(p_name + " ended")
	if p_name == "ThumbsUp":
		selected = false
	if p_name == "Index Pinch":
		pinching = false
		emit_signal("pinch_ended")

var the_box = null

func _on_right_hand_area_entered(area: Area3D) -> void:
	if area.is_in_group("ani_box"):
		the_box = area.get_parent()
		inside = true
	pass # Replace with function body.

var inside = false

func _on_right_hand_area_exited(area: Area3D) -> void:
	if area.get_parent() == the_box:
		inside = false

func _check_for_grab() -> void:
	if pinching and not held_object:
		_try_grab_nearest()
	elif not pinching and held_object:
		_release_held_object()

func _try_grab_nearest() -> void:
	var nearest: RigidBody3D = null
	var nearest_dist: float = INF

	for grabbable in nearby_grabbables:
		if not is_instance_valid(grabbable):
			continue
		if not grabbable is RigidBody3D:
			continue
		var dist = global_position.distance_to(grabbable.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = grabbable as RigidBody3D

	if not nearest:
		return

	# Store original physics state
	_held_original_freeze = nearest.freeze
	_held_original_gravity = nearest.gravity_scale
	_held_original_layer = nearest.collision_layer
	_held_original_mask = nearest.collision_mask

	# Disable physics while held
	nearest.freeze = true
	nearest.linear_velocity = Vector3.ZERO
	nearest.angular_velocity = Vector3.ZERO

	held_object = nearest

func _release_held_object() -> void:
	if not held_object or not is_instance_valid(held_object):
		held_object = null
		return

	var released = held_object
	held_object = null

	# FORCE physics to be active - ignore original state
	released.freeze = false
	released.gravity_scale = 1.0
	released.collision_layer = _held_original_layer
	released.collision_mask = _held_original_mask

	# Clear any residual velocity
	released.linear_velocity = Vector3.ZERO
	released.angular_velocity = Vector3.ZERO

	# Emit signal for other systems (like bin detection)
	object_released.emit(released)

func register_nearby_grabbable(grabbable: Node3D) -> void:
	if grabbable and not nearby_grabbables.has(grabbable):
		nearby_grabbables.append(grabbable)

func unregister_nearby_grabbable(grabbable: Node3D) -> void:
	nearby_grabbables.erase(grabbable)
