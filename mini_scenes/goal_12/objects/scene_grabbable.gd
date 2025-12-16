extends RigidBody3D
## Lightweight grabbable script for scene objects converted at runtime
## Implements the same interface as XRGrabbable for compatibility with Hand
## Syncs a visual node (stored in meta "visual_node") to follow physics body

signal grabbed(hand: Node3D)
signal released(hand: Node3D)
signal placed_in_target(target: Node3D)

@export var grab_distance: float = 0.5
@export var grab_smoothing: float = 15.0  # Higher = faster following, lower = smoother

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

	# Store starting position (local to scene)
	physics_start_local_pos = position

	# Get the visual node reference (set via meta before adding to scene)
	call_deferred("_setup_visual_link")

func _setup_visual_link() -> void:
	if has_meta("visual_node"):
		visual_node = get_meta("visual_node")
		if visual_node and is_instance_valid(visual_node):
			# Store original parent for later use
			visual_original_parent = visual_node.get_parent()

			# Calculate visual's position relative to the scene root by accumulating local transforms
			# This works even when scene scale is 0
			var scene_root = get_parent()
			visual_start_local_pos = _get_position_relative_to(visual_node, scene_root)
			print("SceneGrabbable: Visual node linked - %s at local pos %s" % [visual_node.name, visual_start_local_pos])

func _get_position_relative_to(node: Node3D, relative_to: Node3D) -> Vector3:
	# Accumulate transforms from node up to (but not including) relative_to
	var result_transform = Transform3D.IDENTITY
	var current = node

	while current != null and current != relative_to:
		result_transform = current.transform * result_transform
		current = current.get_parent() as Node3D

	return result_transform.origin

func _physics_process(delta: float) -> void:
	if is_grabbed and grabbing_hand and is_instance_valid(grabbing_hand):
		# Follow hand position with smoothing (reduces jitter from hand tracking)
		global_position = global_position.lerp(grabbing_hand.global_position, grab_smoothing * delta)

	# Always sync visual node to follow physics body movement
	_sync_visual_node()

func _sync_visual_node() -> void:
	if not visual_node or not is_instance_valid(visual_node):
		return

	# Calculate how much the physics body has moved from its start LOCAL position
	var movement = position - physics_start_local_pos

	# Apply that movement to get the new visual position in scene-local coordinates
	var new_visual_local_pos = visual_start_local_pos + movement

	# Convert scene-local to global, then to visual's parent local
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

	print("SceneGrabbable: Grabbed by hand")
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

	print("SceneGrabbable: Released")
	emit_signal("released", released_hand)

func force_release() -> void:
	release()

func on_placed_in_target(target: Node3D) -> void:
	# Also hide the visual node when placed
	if visual_node and is_instance_valid(visual_node):
		visual_node.visible = false
	emit_signal("placed_in_target", target)
