extends MiniScene

var items_sorted: int = 0
var items_correct: int = 0
var trash_bags: Array[RigidBody3D] = []
var intro_sequence: IntroSequence = null

# Bin detection areas
var recycling_bin_area: Area3D = null
var waste_bin_area: Area3D = null

# Track objects currently in bins
var objects_in_recycling: Array[RigidBody3D] = []
var objects_in_waste: Array[RigidBody3D] = []

# Trash bag paths in scene
const TRASH_BAG_PATHS = [
	"Bins/TrashModels/TrashBag1",
	"Bins/TrashModels/TrashBag2",
	"Bins/TrashModels/TrashBag3"
]

func setup_scene() -> void:
	goal_number = 12

	if has_node("IntroSequence"):
		intro_sequence = $IntroSequence
		intro_sequence.sustainabot = sustainabot

	_setup_bin_areas()
	_connect_sustainabot_hit()

func _setup_bin_areas() -> void:
	# Create detection area for RecyclingBin
	if has_node("Bins/TrashModels/RecyclingBin"):
		var recycling_node = get_node("Bins/TrashModels/RecyclingBin")
		recycling_bin_area = _create_bin_area(recycling_node, "recycling")

	# Create detection area for WasteBin
	if has_node("Bins/TrashModels/WasteBin"):
		var waste_node = get_node("Bins/TrashModels/WasteBin")
		waste_bin_area = _create_bin_area(waste_node, "waste")

func _create_bin_area(parent_node: Node3D, bin_type: String) -> Area3D:
	var area = Area3D.new()
	area.name = "BinArea"
	area.collision_layer = 0
	area.collision_mask = 2  # Detect layer 2 (trash bags)
	area.set_meta("bin_type", bin_type)

	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.5, 0.8, 0.5)
	shape.shape = box
	shape.position = Vector3(0, 0.4, 0)
	area.add_child(shape)

	area.body_entered.connect(func(body): _on_bin_body_entered(area, body))
	area.body_exited.connect(func(body): _on_bin_body_exited(area, body))

	parent_node.add_child(area)
	return area

func _on_bin_body_entered(bin_area: Area3D, body: Node3D) -> void:
	if body is RigidBody3D and body in trash_bags:
		var bin_type = bin_area.get_meta("bin_type", "")
		if bin_type == "recycling":
			if body not in objects_in_recycling:
				objects_in_recycling.append(body)
		elif bin_type == "waste":
			if body not in objects_in_waste:
				objects_in_waste.append(body)

func _on_bin_body_exited(bin_area: Area3D, body: Node3D) -> void:
	if body is RigidBody3D:
		var bin_type = bin_area.get_meta("bin_type", "")
		if bin_type == "recycling":
			objects_in_recycling.erase(body)
		elif bin_type == "waste":
			objects_in_waste.erase(body)

func _connect_sustainabot_hit() -> void:
	if sustainabot:
		sustainabot.hit_by_object.connect(_on_sustainabot_hit)

func start_scene() -> void:
	super.start_scene()

	items_sorted = 0
	items_correct = 0

	# Wait for scene fade-in to complete
	await get_tree().create_timer(1.6).timeout

	# Create trash bag physics bodies
	_create_trash_bags()

	# Connect to hand release signals
	_connect_hand_signals()

	# Run intro sequence
	if intro_sequence and sustainabot:
		intro_sequence.intro_completed.connect(_on_intro_completed, CONNECT_ONE_SHOT)
		intro_sequence.start_intro()
	else:
		_enable_trash_bags()

func _connect_hand_signals() -> void:
	# Find hands and connect to their release signals
	var hands = get_tree().get_nodes_in_group("xr_hand")
	for hand in hands:
		if hand.has_signal("object_released"):
			if not hand.object_released.is_connected(_on_object_released):
				hand.object_released.connect(_on_object_released)

	# Also try to find hands by path
	var xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		for child_name in ["left", "right"]:
			var hand = xr_origin.get_node_or_null(child_name)
			if hand and hand.has_signal("object_released"):
				if not hand.object_released.is_connected(_on_object_released):
					hand.object_released.connect(_on_object_released)

func _on_object_released(object: RigidBody3D) -> void:
	if object not in trash_bags:
		return

	# Wait a brief moment for physics to settle
	await get_tree().create_timer(0.3).timeout

	# Check if object is in a bin
	if object in objects_in_recycling:
		var correct = object.is_in_group("recyclable")
		_handle_item_sorted(object, correct)
	elif object in objects_in_waste:
		var correct = object.is_in_group("waste")
		_handle_item_sorted(object, correct)

func _create_trash_bags() -> void:
	for bag_path in TRASH_BAG_PATHS:
		if has_node(bag_path):
			var trash_bag_node = get_node(bag_path)
			var rigid_body = _make_trash_bag_physics(trash_bag_node)
			if rigid_body:
				trash_bags.append(rigid_body)

func _make_trash_bag_physics(trash_bag_node: Node3D) -> RigidBody3D:
	# Find the mesh instance
	var mesh_instance: MeshInstance3D = null
	for child in trash_bag_node.get_children():
		if child is MeshInstance3D:
			mesh_instance = child
			break

	if not mesh_instance:
		push_warning("Goal 12: No mesh in %s" % trash_bag_node.name)
		return null

	# Remove any StaticBody3D from the mesh
	for child in mesh_instance.get_children():
		if child is StaticBody3D:
			child.queue_free()

	# Get the GLOBAL position now (scene is at full scale)
	var world_pos = mesh_instance.global_position

	# Create simple RigidBody3D
	var rigid_body = RigidBody3D.new()
	rigid_body.name = trash_bag_node.name + "_Physics"
	rigid_body.collision_layer = 2  # Layer 2 for trash bags
	rigid_body.collision_mask = 1   # Collide with layer 1 (environment)
	rigid_body.gravity_scale = 1.0
	rigid_body.mass = 0.3
	rigid_body.linear_damp = 2.0
	rigid_body.angular_damp = 2.0
	rigid_body.freeze = true  # Start frozen until intro completes

	# Group for sorting logic
	rigid_body.add_to_group("waste")
	rigid_body.add_to_group("trash_bag")

	# Collision shape
	var col_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.1
	col_shape.shape = sphere
	rigid_body.add_child(col_shape)

	# Store reference to visual node
	rigid_body.set_meta("visual_node", trash_bag_node)

	# Add detection Area3D for hand proximity
	var detect_area = Area3D.new()
	detect_area.name = "HandDetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 1  # Detect layer 1 (hands)
	var detect_shape = CollisionShape3D.new()
	var detect_sphere = SphereShape3D.new()
	detect_sphere.radius = 0.25
	detect_shape.shape = detect_sphere
	detect_area.add_child(detect_shape)
	rigid_body.add_child(detect_area)

	# Connect hand detection
	detect_area.area_entered.connect(func(area): _on_trash_area_entered(rigid_body, area))
	detect_area.area_exited.connect(func(area): _on_trash_area_exited(rigid_body, area))

	# Add to scene tree
	get_tree().root.add_child(rigid_body)

	# Set position AFTER adding to tree
	rigid_body.global_position = world_pos

	return rigid_body

func _on_trash_area_entered(trash_body: RigidBody3D, area: Area3D) -> void:
	var parent = area.get_parent()
	if parent and parent.has_method("register_nearby_grabbable"):
		parent.register_nearby_grabbable(trash_body)

func _on_trash_area_exited(trash_body: RigidBody3D, area: Area3D) -> void:
	var parent = area.get_parent()
	if parent and parent.has_method("unregister_nearby_grabbable"):
		parent.unregister_nearby_grabbable(trash_body)

func _on_intro_completed() -> void:
	if is_active:
		_enable_trash_bags()

func _enable_trash_bags() -> void:
	for bag in trash_bags:
		if is_instance_valid(bag):
			bag.freeze = false

func _physics_process(_delta: float) -> void:
	# Sync visual nodes to follow their physics bodies
	for bag in trash_bags:
		if is_instance_valid(bag) and bag.has_meta("visual_node"):
			var visual = bag.get_meta("visual_node") as Node3D
			if visual and is_instance_valid(visual):
				visual.global_position = bag.global_position
				visual.global_rotation = bag.global_rotation

func _handle_item_sorted(object: RigidBody3D, correct: bool) -> void:
	items_sorted += 1

	# Hide the visual node
	if object.has_meta("visual_node"):
		var visual = object.get_meta("visual_node") as Node3D
		if visual and is_instance_valid(visual):
			visual.visible = false

	if correct:
		items_correct += 1
		if sustainabot:
			sustainabot.set_state("commending")
		report_action(true)
	else:
		if sustainabot:
			sustainabot.set_state("berating")
		report_action(false)

	# Remove from tracked lists
	trash_bags.erase(object)
	objects_in_recycling.erase(object)
	objects_in_waste.erase(object)

	# Queue free after short delay
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(object):
		object.queue_free()

	# End when all items are sorted
	if items_sorted >= 3:
		_finish_task()

func _on_sustainabot_hit(object: Node3D) -> void:
	if not sustainabot:
		return

	var state_name = sustainabot.get_state_name()
	var messages: Array[String]

	match state_name:
		"hit_below_waist":
			messages = ["MY LEGS!", "Watch the shins!", "Ow, my feet!", "Low blow!"]
		"hit_groin":
			messages = ["OOOF!", "Not there!", "That's fighting dirty!", "*high pitched beep*"]
		_:
			messages = ["HEY! That's not a bin!", "Watch where you throw!", "I'm not garbage!", "Ouch! Wrong target!", "The BINS are over there!"]

	var msg = messages[randi() % messages.size()]
	sustainabot.show_speech(msg, 2.0)

	Talo.events.track("Goal 12 trash thrown at bot", {"hit_type": state_name})

func _finish_task() -> void:
	var success_rate = float(items_correct) / 3.0
	var success = success_rate >= 0.7

	if sustainabot:
		if success:
			sustainabot.set_state("celebrating")
			sustainabot.show_speech("Great job! You sorted\n%d/3 correctly!" % items_correct, 3.0)
		else:
			sustainabot.set_state("berating")
			sustainabot.show_speech("Only %d/3 correct.\nTry harder next time!" % items_correct, 3.0)

	await get_tree().create_timer(3.0).timeout

	Talo.events.track("Goal 12 items sorted", {
		"correct": str(items_correct),
		"total": "3",
		"accuracy": str(success_rate)
	})

	complete_task(success)

func end_scene() -> void:
	for bag in trash_bags:
		if is_instance_valid(bag):
			bag.queue_free()
	trash_bags.clear()
	objects_in_recycling.clear()
	objects_in_waste.clear()

	super.end_scene()
