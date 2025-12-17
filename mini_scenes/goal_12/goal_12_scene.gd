extends MiniScene

var items_sorted: int = 0
var items_correct: int = 0
var trash_bags: Array[RigidBody3D] = []
var intro_sequence: IntroSequence = null

# Continuous detection - bin positions cached for every-frame checking
var recycling_bin_center: Vector3 = Vector3.ZERO
var waste_bin_center: Vector3 = Vector3.ZERO
const BIN_DETECTION_RADIUS: float = 0.35  # Detection radius for bins

# Confetti particles for correct placement
var confetti_particles: GPUParticles3D = null

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

	_setup_confetti_particles()
	_connect_sustainabot_hit()

func _cache_bin_positions() -> void:
	# Cache bin positions for continuous detection
	if has_node("Bins/TrashModels/RecyclingBin"):
		var recycling_node = get_node("Bins/TrashModels/RecyclingBin")
		recycling_bin_center = recycling_node.global_position
	else:
		push_warning("Goal 12: RecyclingBin node not found!")

	if has_node("Bins/TrashModels/WasteBin"):
		var waste_node = get_node("Bins/TrashModels/WasteBin")
		waste_bin_center = waste_node.global_position
	else:
		push_warning("Goal 12: WasteBin node not found!")

	print("Goal 12: Bin positions cached - Recycling: %s, Waste: %s" % [recycling_bin_center, waste_bin_center])

func _setup_confetti_particles() -> void:
	confetti_particles = GPUParticles3D.new()
	confetti_particles.emitting = false
	confetti_particles.one_shot = true
	confetti_particles.amount = 50
	confetti_particles.lifetime = 1.5
	confetti_particles.explosiveness = 0.9

	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -5, 0)
	mat.angular_velocity_min = -180.0
	mat.angular_velocity_max = 180.0
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	# Rainbow confetti colors
	mat.color = Color(1, 1, 1, 1)
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 0.2, 0.2))  # Red
	gradient.set_color(1, Color(0.2, 1, 0.2))  # Green
	gradient.add_point(0.25, Color(1, 1, 0.2))  # Yellow
	gradient.add_point(0.5, Color(0.2, 0.5, 1))  # Blue
	gradient.add_point(0.75, Color(1, 0.2, 1))  # Magenta
	var gradient_tex = GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex
	confetti_particles.process_material = mat

	# Simple square mesh for confetti pieces
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.03, 0.03)
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh.material = mesh_mat
	confetti_particles.draw_pass_1 = mesh

	add_child(confetti_particles)

func _emit_confetti_at(position: Vector3) -> void:
	if confetti_particles:
		confetti_particles.global_position = position
		confetti_particles.restart()
		confetti_particles.emitting = true

func _connect_sustainabot_hit() -> void:
	if sustainabot:
		sustainabot.hit_by_object.connect(_on_sustainabot_hit)

func start_scene() -> void:
	super.start_scene()

	# Set Sustainabot skin color to Goal 12 orange (Responsible Consumption)
	if sustainabot:
		sustainabot.set_skin_color(Color("#BF8B2E"))

	items_sorted = 0
	items_correct = 0

	# Wait for scene fade-in to complete
	await get_tree().create_timer(1.6).timeout

	# Cache bin positions for continuous detection
	_cache_bin_positions()

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

# Object released handler (kept for logging - detection is now continuous)
func _on_object_released(object: RigidBody3D) -> void:
	if object not in trash_bags:
		return
	print("Goal 12: Trash bag released - continuous detection will handle it")

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
	rigid_body.mass = 0.3
	rigid_body.linear_damp = 2.0
	rigid_body.angular_damp = 2.0
	# DON'T use freeze = true - frozen bodies don't trigger Area3D body_entered signals!
	# Instead, use gravity_scale = 0 to keep physics active but prevent movement
	rigid_body.freeze = false
	rigid_body.gravity_scale = 0.0  # Disabled until intro completes
	rigid_body.linear_velocity = Vector3.ZERO
	rigid_body.angular_velocity = Vector3.ZERO

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
			# Enable gravity (body was never frozen, just had gravity disabled)
			bag.gravity_scale = 1.0

func _physics_process(delta: float) -> void:
	# Apply manual gravity and sync visuals for trash bags (since world gravity is 0)
	for bag in trash_bags:
		if is_instance_valid(bag):
			# Only apply gravity when enabled (gravity_scale > 0, after intro)
			if bag.gravity_scale > 0:
				bag.apply_central_force(Vector3(0, -9.8 * bag.mass, 0))
				# Keep objects upright - apply corrective torque
				_apply_upright_correction(bag, delta)

			# Always sync visual nodes to follow physics bodies
			if bag.has_meta("visual_node"):
				var visual = bag.get_meta("visual_node") as Node3D
				if visual and is_instance_valid(visual):
					visual.global_position = bag.global_position
					visual.global_rotation = bag.global_rotation

	# Continuous bin detection - check every frame
	_check_trash_in_bins()

# CONTINUOUS BIN DETECTION - checks every physics frame
func _check_trash_in_bins() -> void:
	var items_to_process: Array = []

	for bag in trash_bags:
		if not is_instance_valid(bag):
			continue

		var bag_pos = bag.global_position

		# Check if inside waste bin bounds
		if waste_bin_center != Vector3.ZERO:
			var dist_to_waste = bag_pos.distance_to(waste_bin_center)
			if dist_to_waste < BIN_DETECTION_RADIUS:
				items_to_process.append({"bag": bag, "bin": "waste"})
				continue

		# Check if inside recycling bin bounds
		if recycling_bin_center != Vector3.ZERO:
			var dist_to_recycling = bag_pos.distance_to(recycling_bin_center)
			if dist_to_recycling < BIN_DETECTION_RADIUS:
				items_to_process.append({"bag": bag, "bin": "recycling"})
				continue

	# Process detected items (outside loop to avoid modifying array during iteration)
	for item in items_to_process:
		_process_sorted_trash(item.bag, item.bin)

func _process_sorted_trash(bag: RigidBody3D, bin_type: String) -> void:
	if not is_instance_valid(bag):
		return

	# WASTE bin = correct (trash bags belong there)
	# RECYCLING bin = incorrect (trash bags don't belong there)
	var correct: bool = (bin_type == "waste")

	print("Goal 12: Trash in %s bin, correct=%s" % [bin_type, correct])

	_handle_item_sorted(bag, correct)

func _apply_upright_correction(body: RigidBody3D, delta: float) -> void:
	# Get current up vector and target up vector
	var current_up = body.global_transform.basis.y
	var target_up = Vector3.UP

	# Calculate the rotation needed to align current_up with target_up
	var dot = current_up.dot(target_up)

	# Only apply correction if tilted beyond threshold (dot < 0.99 means > ~8 degrees off)
	if dot < 0.99:
		# Calculate correction axis and angle
		var axis = current_up.cross(target_up)
		if axis.length_squared() > 0.0001:
			axis = axis.normalized()
			# Stronger correction force when more tilted
			var correction_strength = 15.0 * (1.0 - dot)
			body.apply_torque(axis * correction_strength)

			# Also dampen existing angular velocity to prevent spinning
			body.angular_velocity = body.angular_velocity.lerp(Vector3.ZERO, delta * 5.0)

func _handle_item_sorted(object: RigidBody3D, correct: bool) -> void:
	items_sorted += 1

	# Store position for confetti before hiding
	var item_pos = object.global_position

	# Hide the visual node
	if object.has_meta("visual_node"):
		var visual = object.get_meta("visual_node") as Node3D
		if visual and is_instance_valid(visual):
			visual.visible = false

	if correct:
		items_correct += 1
		# Emit confetti celebration at bin location
		_emit_confetti_at(item_pos + Vector3(0, 0.2, 0))
		if sustainabot:
			sustainabot.set_state("commending")
			sustainabot.show_speech("Correct!", 1.5)
		report_action(true)
	else:
		if sustainabot:
			sustainabot.set_state("berating")  # Uses fist-shake animation
			var wrong_messages = ["Wrong bin!", "That's not recycling!", "Trash goes in WASTE!", "Try the other bin!"]
			sustainabot.show_speech(wrong_messages[randi() % wrong_messages.size()], 2.0)
		report_action(false)

	# Remove from tracked list
	trash_bags.erase(object)

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

	super.end_scene()
