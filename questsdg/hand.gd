class_name Hand

extends XRNode3D

signal pinch_started
signal pinch_ended

@export var selected = false
@export var pinching = false

var held_object: XRGrabbable = null
var nearby_grabbables: Array[XRGrabbable] = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$HandPoseDetector.connect("pose_started", _on_hand_pose_detector_pose_started)
	$HandPoseDetector.connect("pose_ended", _on_hand_pose_detector_pose_ended)
	pass # Replace with function body.

var force = Vector3.ZERO
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	_check_for_grab()


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
	var nearest: XRGrabbable = null
	var nearest_dist: float = INF

	for grabbable in nearby_grabbables:
		if not is_instance_valid(grabbable):
			continue
		var dist = global_position.distance_to(grabbable.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = grabbable

	if nearest and nearest.try_grab(self):
		held_object = nearest

func _release_held_object() -> void:
	if held_object:
		held_object.release()
		held_object = null

func register_nearby_grabbable(grabbable: XRGrabbable) -> void:
	if grabbable and not nearby_grabbables.has(grabbable):
		nearby_grabbables.append(grabbable)

func unregister_nearby_grabbable(grabbable: XRGrabbable) -> void:
	nearby_grabbables.erase(grabbable)
