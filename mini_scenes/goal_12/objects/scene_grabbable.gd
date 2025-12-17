extends RigidBody3D
## What: Runtime grabbable with visual/physics sync
## Who: XRGrabbable interface, goal_12_scene object conversion
## Why: Convert static scene objects to pickable waste items

signal grabbed(hand: Node3D)
signal released(hand: Node3D)
signal placed_in_target(target: Node3D)

@export var grab_distance: float = 0.5
@export var grab_smoothing: float = 15.0

var is_grabbed: bool = false
var grabbing_hand: Node3D = null
var original_freeze: bool = false
var original_gravity_scale: float = 1.0
var visual_node: Node3D = null
var physics_start_local_pos: Vector3 = Vector3.ZERO
var visual_start_local_pos: Vector3 = Vector3.ZERO
var visual_original_parent: Node3D = null

func _ready() -> void:
	original_freeze = freeze
	original_gravity_scale = gravity_scale
	collision_layer = 2
	collision_mask = 7
	physics_start_local_pos = position
	call_deferred("_setup_visual_link")

func _setup_visual_link() -> void:
	if has_meta("visual_node"):
		visual_node = get_meta("visual_node")
		if visual_node and is_instance_valid(visual_node):
			visual_original_parent = visual_node.get_parent()
			var scene_root = get_parent()
			visual_start_local_pos = _get_position_relative_to(visual_node, scene_root)

func _get_position_relative_to(node: Node3D, relative_to: Node3D) -> Vector3:
	# Accumulate transforms up tree to relative_to
	var result_transform = Transform3D.IDENTITY
	var current = node
	
	while current != null and current != relative_to:
		result_transform = current.transform * result_transform
		current = current.get_parent() as Node3D
	
	return result_transform.origin

func _physics_process(delta: float) -> void:
	if is_grabbed and grabbing_hand and is_instance_valid(grabbing_hand):
		global_position = global_position.lerp(grabbing_hand.global_position, grab_smoothing * delta)
	
	_sync_visual_node()

func _sync_visual_node() -> void:
	if not visual_node or not is_instance_valid(visual_node):
		return
	
	# Visual follows physics body offset
	var movement = position - physics_start_local_pos
	var new_visual_local_pos = visual_start_local_pos + movement
	
	var scene_root = get_parent()
	if scene_root and visual_original_parent and is_instance_valid(visual_original_parent):
		var new_global_pos = scene_root.to_global(new_visual_local_pos)
		visual_node.global_position = new_global_pos

func try_grab(hand: Node3D) -> bool:
	if is_grabbed:
		return false
	
	var is_pinching = hand.get("pinching")
	if not is_pinching:
		return false
	
	var distance = global_position.distance_to(hand.global_position)
	if distance > grab_distance:
		return false
	
	_do_grab(hand)
	return true

func _do_grab(hand: Node3D) -> void:
	is_grabbed = true
	grabbing_hand = hand
	original_freeze = freeze
	original_gravity_scale = gravity_scale
	freeze = true
	gravity_scale = 0.0
	emit_signal("grabbed", hand)

func release() -> void:
	if not is_grabbed:
		return
	
	var released_hand = grabbing_hand
	is_grabbed = false
	grabbing_hand = null
	freeze = false
	gravity_scale = original_gravity_scale
	linear_velocity = Vector3.ZERO
	emit_signal("released", released_hand)

func force_release() -> void:
	release()

func on_placed_in_target(target: Node3D) -> void:
	if visual_node and is_instance_valid(visual_node):
		visual_node.visible = false
	emit_signal("placed_in_target", target)
