extends MiniScene

# Game state
var items_sorted: int = 0
var items_correct: int = 0
const TOTAL_ITEMS: int = 10
const FALL_Y_THRESHOLD: float = -2.0  # Items below this are cleaned up
const MAX_ACTIVE_ITEMS: int = 3  # Max concurrent food items

# Conveyor state
var conveyor_active: bool = false
var belt_speed: float = 0.8  # meters/second
var _belt_scroll_offset: float = 0.0

# Current food items
var current_food_item: RigidBody3D = null
var food_items: Array[RigidBody3D] = []

# Sorting detection
var crate_area: Area3D = null  # Good food target
var bin_area: Area3D = null    # Bad food target
var objects_in_crate: Array[RigidBody3D] = []
var objects_in_bin: Array[RigidBody3D] = []
var crate_bounds: AABB = AABB()  # Position-based detection bounds
var bin_bounds: AABB = AABB()

# References
var intro_sequence: IntroSequence = null
var spawn_point: Marker3D = null
var button_area: Area3D = null
var score_label: Label3D = null
var progress_label: Label3D = null
var instruction_label: Label3D = null
var conveyor_belt: Node3D = null
var start_stop_button: MeshInstance3D = null

# Preloaded scenes
var good_food_scene: PackedScene = null
var bad_food_scene: PackedScene = null

# Conveyor belt materials
var conveyor_meshes: Array[MeshInstance3D] = []
var original_materials: Array[Material] = []

# XR references
var xr_origin: XROrigin3D = null
var xr_camera: XRCamera3D = null

# Sustainabot follow behavior
var follow_threshold: float = 2.5  # meters
var is_following: bool = false
var follow_target_pos: Vector3 = Vector3.ZERO

# Confetti particles
var confetti_particles: GPUParticles3D = null

# Button cooldown
var _button_cooldown: float = 0.0

# Idle animation cycling
var idle_animation_timer: float = 0.0
const IDLE_ANIMATION_INTERVAL: float = 4.0  # Change idle anim every 4 seconds

const IDLE_ANIMS: Array[String] = [
	"Idle0", "DigAndPlantSeeds0", "Rummaging0", "LookOverShoulder0"
]

# Food model names from GLTF
const FOOD_MODELS: Array[String] = [
	"F_Latin_Corn_LOD0",
	"F_Latin_Taco_Classic_LOD0",
	"F_Europe_Bakery_Waffles_LOD0",
	"F_Asia_Onigiri_LOD0",
	"F_Asia_Takoyaki_Small_LOD0",
	"F_Europe_Bakery_Donut_Chocolate_LOD0",
	"F_Europe_Bakery_French_Baguette_Half_LOD0",
	"F_Europe_Burger_Hamburger_LOD0",
	"F_Europe_Hotdog_Hotdog_Classic_LOD0",
	"F_Europe_Pasta_LOD0",
	"F_Europe_Pizza_Pepperoni_LOD0",
	"F_Asia_Dumplings_LOD0"
]

# GLTF path prefix
const GLTF_PATH_PREFIX = "Sketchfab_model/30791303cda94400ad9929f2e1788be4_fbx/RootNode/"

func setup_scene() -> void:
	goal_number = 2
	print("Goal 2: setup_scene() starting...")

	_get_references()
	print("Goal 2: References obtained")

	_preload_food_scenes()
	print("Goal 2: Food scenes preloaded")

	_setup_button_detection()
	print("Goal 2: Button detection setup")

	# NOTE: _setup_sorting_areas() moved to start_scene() after fade-in
	# because global_position is (0,0,0) before scene is positioned

	_setup_confetti_particles()
	print("Goal 2: Confetti particles setup")

	_hide_display_foods()
	print("Goal 2: Display foods hidden")

	_connect_sustainabot_hit()
	print("Goal 2: setup_scene() complete")

func _get_references() -> void:
	if has_node("IntroSequence"):
		intro_sequence = $IntroSequence
		intro_sequence.sustainabot = sustainabot

	if has_node("FoodSpawnPoint"):
		spawn_point = $FoodSpawnPoint

	if has_node("ConveyorBelt"):
		conveyor_belt = $ConveyorBelt
		if conveyor_belt.has_node("StartStopButton"):
			start_stop_button = conveyor_belt.get_node("StartStopButton")
			if start_stop_button.has_node("ButtonArea"):
				button_area = start_stop_button.get_node("ButtonArea")

	if has_node("UI/ScoreLabel"):
		score_label = $UI/ScoreLabel
	if has_node("UI/ProgressLabel"):
		progress_label = $UI/ProgressLabel
	if has_node("InstructionLabel"):
		instruction_label = $InstructionLabel

	# Get XR references
	xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		xr_camera = xr_origin.get_node_or_null("XRCamera3D")

func _preload_food_scenes() -> void:
	# Use load() instead of preload() for better error handling
	var good_path = "res://mini_scenes/goal_2/assets/free_hyper_casual_street_food_pack/good_food.tscn"
	var bad_path = "res://mini_scenes/goal_2/assets/free_hyper_casual_street_food_pack/bad_food.tscn"

	if ResourceLoader.exists(good_path):
		good_food_scene = load(good_path)
	else:
		push_error("Goal 2: Could not find good_food.tscn at " + good_path)

	if ResourceLoader.exists(bad_path):
		bad_food_scene = load(bad_path)
	else:
		push_error("Goal 2: Could not find bad_food.tscn at " + bad_path)

func _hide_display_foods() -> void:
	# Hide the display foods in the scene (they're just for reference in editor)
	if has_node("Foods"):
		$Foods.visible = false

func _setup_button_detection() -> void:
	if button_area:
		button_area.area_entered.connect(_on_button_area_entered)
		print("Goal 2: Button area connected")

func _setup_sorting_areas() -> void:
	# Create detection areas at SCENE ROOT (not as children of scaled containers)

	# Crate area (for good food)
	if has_node("Sorting/Crate"):
		var crate_node = $Sorting/Crate
		var world_pos = crate_node.global_position
		crate_area = _create_sorting_area_at_position(world_pos, "crate", Vector3(0.5, 0.5, 0.5))
	else:
		push_warning("Goal 2: Crate node not found!")

	# Bin area (for bad food)
	if has_node("Sorting/FoodBin"):
		var bin_node = $Sorting/FoodBin
		var world_pos = bin_node.global_position
		bin_area = _create_sorting_area_at_position(world_pos, "bin", Vector3(0.5, 0.6, 0.5))
	else:
		push_warning("Goal 2: FoodBin node not found!")

func _create_sorting_area_at_position(world_pos: Vector3, container_type: String, size: Vector3) -> Area3D:
	var area = Area3D.new()
	area.name = "SortingArea_" + container_type
	area.collision_layer = 0
	area.collision_mask = 2  # Detect layer 2 (food items)
	area.monitoring = true
	area.monitorable = false
	area.set_meta("container_type", container_type)

	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)

	area.body_entered.connect(func(body): _on_sorting_body_entered(area, body))
	area.body_exited.connect(func(body): _on_sorting_body_exited(area, body))

	# Add to scene root so it's not affected by container scaling
	add_child(area)

	# Position at container location with offset to opening
	area.global_position = world_pos + Vector3(0, 0.2, 0)

	print("Goal 2: Created SortingArea for %s at %s" % [container_type, area.global_position])
	return area

func _calculate_container_bounds() -> void:
	# Calculate AABB bounds for position-based detection (larger for reliability)
	if crate_area:
		var pos = crate_area.global_position
		# Larger bounds (0.6m cube) for more forgiving detection
		crate_bounds = AABB(pos - Vector3(0.3, 0.3, 0.3), Vector3(0.6, 0.6, 0.6))
		print("Goal 2: Crate bounds calculated at %s" % crate_bounds)
	if bin_area:
		var pos = bin_area.global_position
		# Larger bounds for bin
		bin_bounds = AABB(pos - Vector3(0.3, 0.35, 0.3), Vector3(0.6, 0.7, 0.6))
		print("Goal 2: Bin bounds calculated at %s" % bin_bounds)

func _is_position_in_container(pos: Vector3, container_type: String) -> bool:
	var bounds = crate_bounds if container_type == "crate" else bin_bounds
	# Expand bounds by 0.2m for more forgiving detection
	return bounds.grow(0.2).has_point(pos)

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
	mat.color = Color(1, 1, 1, 1)

	# Rainbow confetti colors
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
	if sustainabot and sustainabot.has_signal("hit_by_object"):
		if not sustainabot.hit_by_object.is_connected(_on_sustainabot_hit):
			sustainabot.hit_by_object.connect(_on_sustainabot_hit)

func start_scene() -> void:
	super.start_scene()

	# Reset state
	items_sorted = 0
	items_correct = 0
	conveyor_active = false
	_belt_scroll_offset = 0.0

	_update_ui()

	# Wait for scene fade-in
	await get_tree().create_timer(1.6).timeout

	# Setup sorting areas NOW (scene is positioned at XR origin)
	_setup_sorting_areas()
	print("Goal 2: Sorting areas setup (after positioning)")

	# Calculate container bounds for position-based detection
	_calculate_container_bounds()

	# Connect hand signals
	_connect_hand_signals()

	# Run intro sequence
	if intro_sequence and sustainabot:
		intro_sequence.intro_completed.connect(_on_intro_completed, CONNECT_ONE_SHOT)
		intro_sequence.start_intro()
	else:
		_enable_gameplay()

func _connect_hand_signals() -> void:
	# Find hands and connect to their release signals
	var hands = get_tree().get_nodes_in_group("xr_hand")
	for hand in hands:
		if hand.has_signal("object_released"):
			if not hand.object_released.is_connected(_on_object_released):
				hand.object_released.connect(_on_object_released)

	# Also try to find hands by path
	if xr_origin:
		for child_name in ["left", "right"]:
			var hand = xr_origin.get_node_or_null(child_name)
			if hand and hand.has_signal("object_released"):
				if not hand.object_released.is_connected(_on_object_released):
					hand.object_released.connect(_on_object_released)

func _on_intro_completed() -> void:
	if is_active:
		_enable_gameplay()

func _enable_gameplay() -> void:
	if progress_label:
		progress_label.text = "Touch the red button to start!"
	print("Goal 2: Gameplay enabled")

func _on_button_area_entered(area: Area3D) -> void:
	if _button_cooldown > 0:
		return

	# Check if it's a hand
	var parent = area.get_parent()
	var is_hand = "hand" in area.name.to_lower() or (parent and "hand" in parent.name.to_lower())

	if is_hand:
		_toggle_conveyor()
		_button_cooldown = 1.0  # Prevent rapid toggling
		_animate_button_press()
		print("Goal 2: Button pressed by hand")

func _toggle_conveyor() -> void:
	conveyor_active = not conveyor_active

	# Update button color
	if start_stop_button:
		var mat = start_stop_button.get_surface_override_material(0)
		if mat == null:
			mat = StandardMaterial3D.new()
			start_stop_button.set_surface_override_material(0, mat)
		if mat is StandardMaterial3D:
			mat.albedo_color = Color(0.1, 0.7, 0.1) if conveyor_active else Color(0.7, 0.1, 0.1)

	if conveyor_active:
		if progress_label:
			progress_label.text = "Conveyor running - sort the food!"

		# Try to spawn if game not finished (removed null check - allow multiple items)
		if items_sorted < TOTAL_ITEMS:
			await get_tree().create_timer(0.5).timeout
			# Re-check conveyor still active after await
			if conveyor_active:
				_spawn_next_food_item()
	else:
		if progress_label:
			progress_label.text = "Conveyor stopped"

func _animate_button_press() -> void:
	if start_stop_button:
		var original_scale = start_stop_button.scale
		var tween = create_tween()
		tween.tween_property(start_stop_button, "scale", original_scale * 0.8, 0.1)
		tween.tween_property(start_stop_button, "scale", original_scale, 0.1)

func _spawn_next_food_item() -> void:
	if items_sorted >= TOTAL_ITEMS:
		return

	if not conveyor_active:
		return

	# Limit concurrent items to prevent flooding
	if food_items.size() >= MAX_ACTIVE_ITEMS:
		return

	# Random selection: good or bad food (50/50)
	var is_bad = randf() > 0.5
	var food_scene = bad_food_scene if is_bad else good_food_scene

	# Safety check - if scene not loaded, skip
	if food_scene == null:
		push_error("Goal 2: Food scene not loaded!")
		return

	# Pick random food type
	var food_type_index = randi() % FOOD_MODELS.size()
	var food_name = FOOD_MODELS[food_type_index]

	print("Goal 2: Spawning %s food: %s" % ["bad" if is_bad else "good", food_name])

	# Create physics body for the food item
	var food_body = await _create_food_physics_body(food_scene, food_name, is_bad)

	if food_body:
		current_food_item = food_body
		food_items.append(food_body)

func _create_food_physics_body(food_scene: PackedScene, food_name: String, is_bad: bool) -> RigidBody3D:
	# Instance the full food scene to find the specific mesh
	var temp_scene = food_scene.instantiate()

	# Navigate to find the specific food mesh
	# Path: Sketchfab_model/.../RootNode/{food_name}/{food_name}_streetFood_0
	var mesh_path = GLTF_PATH_PREFIX + food_name + "/" + food_name + "_streetFood_0"
	var mesh_node = temp_scene.get_node_or_null(mesh_path)

	if not mesh_node or not mesh_node is MeshInstance3D:
		# Try alternative: search recursively
		mesh_node = _find_food_mesh_recursive(temp_scene, food_name)

	if not mesh_node:
		temp_scene.queue_free()
		push_warning("Goal 2: Could not find mesh for " + food_name)
		return null

	# Create RigidBody3D
	var rigid_body = RigidBody3D.new()
	rigid_body.name = food_name + "_Physics"
	rigid_body.collision_layer = 2  # Layer 2 for food items
	rigid_body.collision_mask = 1   # Collide with environment
	rigid_body.mass = 0.5  # Heavier to prevent bouncing/flying
	rigid_body.linear_damp = 8.0  # High damping to settle quickly
	rigid_body.angular_damp = 8.0  # High angular damping
	rigid_body.freeze = false
	rigid_body.gravity_scale = 0.0  # Will enable after spawn

	# Mark as good or bad
	rigid_body.set_meta("is_bad", is_bad)
	rigid_body.set_meta("food_name", food_name)
	rigid_body.add_to_group("food_item")
	if is_bad:
		rigid_body.add_to_group("bad_food")
	else:
		rigid_body.add_to_group("good_food")

	# Clone the mesh and reparent
	var mesh_clone = mesh_node.duplicate() as MeshInstance3D
	mesh_clone.name = "FoodMesh"
	mesh_clone.transform = Transform3D.IDENTITY
	# Scale food to reasonable size (GLTF models are large, need scaling down)
	mesh_clone.scale = Vector3.ONE * 0.012
	rigid_body.add_child(mesh_clone)

	# Store reference to visual mesh
	rigid_body.set_meta("visual_mesh", mesh_clone)

	# Collision shape - approximate sphere
	var col_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.08
	col_shape.shape = sphere
	rigid_body.add_child(col_shape)

	# Hand detection area for grabbing
	var detect_area = Area3D.new()
	detect_area.name = "HandDetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 1  # Detect hands
	var detect_shape = CollisionShape3D.new()
	var detect_sphere = SphereShape3D.new()
	detect_sphere.radius = 0.2
	detect_shape.shape = detect_sphere
	detect_area.add_child(detect_shape)
	rigid_body.add_child(detect_area)

	# Connect hand detection
	detect_area.area_entered.connect(func(area): _on_food_area_entered(rigid_body, area))
	detect_area.area_exited.connect(func(area): _on_food_area_exited(rigid_body, area))

	# Add to scene tree
	get_tree().root.add_child(rigid_body)

	# Set spawn position - lowered to be near belt surface
	var spawn_pos = Vector3(0, 0.5, 0.3)
	if spawn_point:
		spawn_pos = spawn_point.global_position
		spawn_pos.y = 0.5  # Override Y to be near belt surface
	rigid_body.global_position = spawn_pos

	# Clean up temp scene
	temp_scene.queue_free()

	# Enable gravity after a short delay (let it appear first)
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(rigid_body):
		rigid_body.gravity_scale = 1.0

	return rigid_body

func _find_food_mesh_recursive(node: Node, food_name: String) -> MeshInstance3D:
	# Check if this node matches
	if node.name.begins_with(food_name) and node is MeshInstance3D:
		return node

	# Check children
	for child in node.get_children():
		var found = _find_food_mesh_recursive(child, food_name)
		if found:
			return found

	return null

func _on_food_area_entered(food_body: RigidBody3D, area: Area3D) -> void:
	var parent = area.get_parent()
	if parent and parent.has_method("register_nearby_grabbable"):
		parent.register_nearby_grabbable(food_body)

func _on_food_area_exited(food_body: RigidBody3D, area: Area3D) -> void:
	var parent = area.get_parent()
	if parent and parent.has_method("unregister_nearby_grabbable"):
		parent.unregister_nearby_grabbable(food_body)

func _on_sorting_body_entered(sorting_area: Area3D, body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("food_item"):
		var container_type = sorting_area.get_meta("container_type", "")
		print("Goal 2: Food entered %s" % container_type)
		if container_type == "crate":
			if body not in objects_in_crate:
				objects_in_crate.append(body)
		elif container_type == "bin":
			if body not in objects_in_bin:
				objects_in_bin.append(body)

func _on_sorting_body_exited(sorting_area: Area3D, body: Node3D) -> void:
	if body is RigidBody3D:
		var container_type = sorting_area.get_meta("container_type", "")
		if container_type == "crate":
			objects_in_crate.erase(body)
		elif container_type == "bin":
			objects_in_bin.erase(body)

func _on_object_released(object: RigidBody3D) -> void:
	if not object.is_in_group("food_item"):
		return

	print("Goal 2: Object released, waiting for physics to settle...")

	# Wait for physics to settle (increased from 0.3 to 0.5 for reliability)
	await get_tree().create_timer(0.5).timeout

	if not is_instance_valid(object):
		return

	var is_bad = object.get_meta("is_bad", false)
	var obj_pos = object.global_position

	# Multi-method detection for reliability

	# Method 1: Position-based detection (most reliable)
	var in_crate = _is_position_in_container(obj_pos, "crate")
	var in_bin = _is_position_in_container(obj_pos, "bin")

	# Method 2: Area3D tracking arrays (fallback)
	if not in_crate and not in_bin:
		in_crate = object in objects_in_crate
		in_bin = object in objects_in_bin

	# Method 3: get_overlapping_bodies (fallback)
	if not in_crate and not in_bin:
		if crate_area:
			in_crate = object in crate_area.get_overlapping_bodies()
		if bin_area:
			in_bin = object in bin_area.get_overlapping_bodies()

	print("Goal 2: Detection result - in_crate: %s, in_bin: %s, pos: %s" % [in_crate, in_bin, obj_pos])

	# Handle sorting result
	if in_crate:
		var correct = not is_bad  # Good food in crate = correct
		_handle_item_sorted(object, correct)
	elif in_bin:
		var correct = is_bad  # Bad food in bin = correct
		_handle_item_sorted(object, correct)
	else:
		print("Goal 2: Object not in any container, position: %s" % obj_pos)

func _handle_item_sorted(object: RigidBody3D, correct: bool) -> void:
	items_sorted += 1

	var item_pos = object.global_position
	var food_name = object.get_meta("food_name", "food")
	var is_bad = object.get_meta("is_bad", false)

	if correct:
		items_correct += 1
		_emit_confetti_at(item_pos + Vector3(0, 0.2, 0))

		if sustainabot:
			sustainabot.set_state("commending")
			var messages = ["Great sorting!", "Correct!", "Well done!", "That's right!", "Perfect!"]
			sustainabot.show_speech(messages[randi() % messages.size()], 1.5)

		report_action(true)
	else:
		if sustainabot:
			sustainabot.set_state("berating")
			var messages: Array[String]
			if is_bad:
				messages = ["That was spoiled!", "Purple = bad food!", "Check the color!", "That's rotten!"]
			else:
				messages = ["That was good food!", "Don't waste it!", "Good food goes in the crate!", "Save the good food!"]
			sustainabot.show_speech(messages[randi() % messages.size()], 2.0)

		report_action(false)

	_update_ui()

	# Cleanup food item
	food_items.erase(object)
	objects_in_crate.erase(object)
	objects_in_bin.erase(object)

	if object == current_food_item:
		current_food_item = null

	# Remove after short delay
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(object):
		object.queue_free()

	# Spawn next or finish
	if items_sorted >= TOTAL_ITEMS:
		_finish_task()
	elif conveyor_active:
		await get_tree().create_timer(1.0).timeout
		_spawn_next_food_item()

func _update_ui() -> void:
	if score_label:
		score_label.text = "Score: %d/%d" % [items_correct, TOTAL_ITEMS]

		# Color based on performance
		var ratio = float(items_correct) / max(items_sorted, 1)
		if ratio >= 0.7:
			score_label.modulate = Color(0.2, 1, 0.2)  # Green
		elif ratio >= 0.5:
			score_label.modulate = Color(1, 1, 0.2)   # Yellow
		else:
			score_label.modulate = Color(1, 0.4, 0.4)  # Red

func _physics_process(delta: float) -> void:
	if not is_active:
		return

	# Update button cooldown
	if _button_cooldown > 0:
		_button_cooldown -= delta

	# Move items on conveyor belt and apply physics
	_apply_food_physics(delta)

	# Animate conveyor belt texture
	if conveyor_active:
		_update_conveyor_animation(delta)

	# Check Sustainabot follow behavior
	_check_sustainabot_follow(delta)

	# Cycle idle animations continuously
	_update_idle_animation(delta)

	# Clean up items that have fallen below the scene
	_cleanup_fallen_items()

func _apply_food_physics(delta: float) -> void:
	for food in food_items:
		if is_instance_valid(food) and food.gravity_scale > 0:
			# Apply manual gravity (world gravity is 0)
			food.apply_central_force(Vector3(0, -9.8 * food.mass, 0))

			# If on conveyor belt and conveyor is active, push toward table
			if conveyor_active and _is_on_conveyor_belt(food):
				var belt_direction = Vector3(0, 0, -1)  # Toward tables (negative Z)
				var belt_force = belt_direction * belt_speed * 30.0 * food.mass
				food.apply_central_force(belt_force)

			# Keep food upright
			_apply_upright_correction(food, delta)

func _is_on_conveyor_belt(food: RigidBody3D) -> bool:
	# Check if food is in the conveyor belt area
	# Expanded bounds to include falling trajectory from spawn
	var pos = food.global_position
	# Y: from spawn height (0.5) down to belt surface (0.1)
	# X: belt width
	# Z: from spawn point to near tables
	return pos.y < 1.0 and pos.y > 0.1 and abs(pos.x) < 0.5 and pos.z > -1.0 and pos.z < 0.5

func _apply_upright_correction(body: RigidBody3D, delta: float) -> void:
	var current_up = body.global_transform.basis.y
	var target_up = Vector3.UP

	var dot = current_up.dot(target_up)

	if dot < 0.99:
		var axis = current_up.cross(target_up)
		if axis.length_squared() > 0.0001:
			axis = axis.normalized()
			var correction_strength = 12.0 * (1.0 - dot)
			body.apply_torque(axis * correction_strength)
			body.angular_velocity = body.angular_velocity.lerp(Vector3.ZERO, delta * 5.0)

func _update_conveyor_animation(delta: float) -> void:
	# Simple visual indication - the belt texture would scroll if we had a shader
	# For now, we'll use this to track the animation state
	_belt_scroll_offset += belt_speed * delta
	_belt_scroll_offset = fmod(_belt_scroll_offset, 1.0)

func _cleanup_fallen_items() -> void:
	var items_to_remove: Array[RigidBody3D] = []

	for food in food_items:
		if is_instance_valid(food) and food.global_position.y < FALL_Y_THRESHOLD:
			print("Goal 2: Food item fell below threshold, cleaning up: %s" % food.name)
			items_to_remove.append(food)

	for food in items_to_remove:
		food_items.erase(food)
		objects_in_crate.erase(food)
		objects_in_bin.erase(food)
		if food == current_food_item:
			current_food_item = null
		food.queue_free()

	# Auto-spawn after cleanup if conveyor running
	if items_to_remove.size() > 0 and conveyor_active and items_sorted < TOTAL_ITEMS:
		call_deferred("_spawn_next_food_item")

func _check_sustainabot_follow(delta: float) -> void:
	if not sustainabot or not xr_camera:
		return

	# Don't follow during intro or celebration
	var state_name = sustainabot.get_state_name()
	if state_name in ["sprinting", "celebrating", "instructing"]:
		is_following = false
		return

	var player_pos = xr_camera.global_position
	player_pos.y = sustainabot.global_position.y  # Ignore vertical

	var bot_pos = sustainabot.global_position

	var distance = player_pos.distance_to(bot_pos)

	if distance > follow_threshold and not is_following:
		_start_following_player()
	elif distance < follow_threshold * 0.6 and is_following:
		_stop_following_player()

	# Move toward player if following
	if is_following:
		var direction = (player_pos - bot_pos).normalized()
		var target_pos = player_pos - direction * 1.8  # Stay 1.8m away
		sustainabot.global_position = sustainabot.global_position.move_toward(target_pos, delta * 1.2)
		sustainabot.look_at_player(player_pos)

func _start_following_player() -> void:
	is_following = true
	sustainabot.set_state("sprinting")
	print("Goal 2: Sustainabot starting to follow player")

func _stop_following_player() -> void:
	is_following = false
	sustainabot.set_state("idle")
	if xr_camera:
		sustainabot.look_at_player(xr_camera.global_position)
	print("Goal 2: Sustainabot stopped following")

func _update_idle_animation(delta: float) -> void:
	if not sustainabot:
		return

	var state = sustainabot.get_state_name()
	# Only cycle idle animations when bot is in idle state
	if state != "idle":
		idle_animation_timer = 0.0
		return

	idle_animation_timer += delta
	if idle_animation_timer >= IDLE_ANIMATION_INTERVAL:
		idle_animation_timer = 0.0
		# Play random idle animation
		var anim = IDLE_ANIMS[randi() % IDLE_ANIMS.size()]
		if sustainabot.animation_player and sustainabot.animation_player.has_animation(anim):
			sustainabot.animation_player.play(anim)

func _on_sustainabot_hit(object: Node3D) -> void:
	if not sustainabot:
		return

	var state_name = sustainabot.get_state_name()
	var messages: Array[String]

	match state_name:
		"hit_below_waist":
			messages = ["MY LEGS!", "Watch it!", "Ow, my feet!"]
		"hit_groin":
			messages = ["OOOF!", "Not there!", "*high pitched beep*"]
		_:
			messages = ["HEY! That's not food!", "Don't throw at me!", "The BINS are over there!", "I'm not a trash can!"]

	var msg = messages[randi() % messages.size()]
	sustainabot.show_speech(msg, 2.0)

	Talo.events.track("Goal 2 food thrown at bot", {"hit_type": state_name})

func _finish_task() -> void:
	conveyor_active = false

	var success_rate = float(items_correct) / float(TOTAL_ITEMS)
	var success = success_rate >= 0.7  # 70% threshold

	if sustainabot:
		if success:
			sustainabot.set_state("celebrating")
			if items_correct == TOTAL_ITEMS:
				sustainabot.show_speech("PERFECT!\n%d/%d correct!" % [items_correct, TOTAL_ITEMS], 4.0)
			else:
				sustainabot.show_speech("Great job!\n%d/%d correct!" % [items_correct, TOTAL_ITEMS], 4.0)
		else:
			sustainabot.set_state("berating")
			sustainabot.show_speech("Only %d/%d correct.\nFood waste is serious!" % [items_correct, TOTAL_ITEMS], 4.0)

	if score_label:
		score_label.text = "Final: %d/%d" % [items_correct, TOTAL_ITEMS]
		score_label.modulate = Color.GREEN if success else Color.RED

	if progress_label:
		progress_label.text = "Task Complete!"

	await get_tree().create_timer(4.0).timeout

	Talo.events.track("Goal 2 completed", {
		"correct": str(items_correct),
		"total": str(TOTAL_ITEMS),
		"accuracy": str(success_rate)
	})

	complete_task(success)

func end_scene() -> void:
	# Cleanup all food items
	for food in food_items:
		if is_instance_valid(food):
			food.queue_free()
	food_items.clear()
	objects_in_crate.clear()
	objects_in_bin.clear()
	current_food_item = null
	conveyor_active = false
	is_following = false

	super.end_scene()
