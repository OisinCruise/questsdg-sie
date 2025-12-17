extends MiniScene
## What: Food sorting conveyor belt game - sort edible/waste
## Who: MiniScene parent, XROrigin for camera tracking
## Why: Goal 2 zero hunger - reduce food waste through sorting

var items_sorted: int = 0
var items_correct: int = 0
const TOTAL_ITEMS: int = 10
const CONTAINER_RADIUS: float = 0.4

var crate_center: Vector3 = Vector3.ZERO  # edible target
var bin_center: Vector3 = Vector3.ZERO    # waste target
var food_items: Array[RigidBody3D] = []
var current_food_item: RigidBody3D = null
var conveyor_active: bool = false
var belt_speed: float = 0.8

var spawn_point: Marker3D = null
var button_area: Area3D = null
var score_label: Label3D = null
var progress_label: Label3D = null
var conveyor_belt: Node3D = null
var start_stop_button: MeshInstance3D = null
var crate_node: Node3D = null
var bin_node: Node3D = null
var barrier_area: Area3D = null
var xr_origin: XROrigin3D = null
var xr_camera: XRCamera3D = null
var _button_cooldown: float = 0.0

var good_food_scene: PackedScene = null
var bad_food_scene: PackedScene = null

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

const GLTF_PATH_PREFIX = "Sketchfab_model/30791303cda94400ad9929f2e1788be4_fbx/RootNode/"

func setup_scene() -> void:
	goal_number = 2
	_get_references()
	_preload_food_scenes()
	_setup_button_detection()
	_setup_barrier_detection()
	_hide_display_foods()

func _get_references() -> void:
	if has_node("FoodSpawnPoint"):
		spawn_point = $FoodSpawnPoint

	if has_node("ConveyorBelt"):
		conveyor_belt = $ConveyorBelt
		if conveyor_belt.has_node("StartStopButton"):
			start_stop_button = conveyor_belt.get_node("StartStopButton")
			if start_stop_button.has_node("ButtonArea"):
				button_area = start_stop_button.get_node("ButtonArea")

	if has_node("Sorting/Crate"):
		crate_node = $Sorting/Crate
	if has_node("Sorting/FoodBin"):
		bin_node = $Sorting/FoodBin
	if has_node("Tables/TableBarrier/BarrierArea"):
		barrier_area = $Tables/TableBarrier/BarrierArea

	if has_node("UI/ScoreLabel"):
		score_label = $UI/ScoreLabel
	if has_node("UI/ProgressLabel"):
		progress_label = $UI/ProgressLabel

	xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		xr_camera = xr_origin.get_node_or_null("XRCamera3D")

func _preload_food_scenes() -> void:
	var good_path = "res://mini_scenes/goal_2/assets/free_hyper_casual_street_food_pack/good_food.tscn"
	var bad_path = "res://mini_scenes/goal_2/assets/free_hyper_casual_street_food_pack/bad_food.tscn"

	if ResourceLoader.exists(good_path):
		good_food_scene = load(good_path)
	if ResourceLoader.exists(bad_path):
		bad_food_scene = load(bad_path)

func _hide_display_foods() -> void:
	if has_node("Foods"):
		$Foods.visible = false

func _cache_container_positions() -> void:
	if crate_node:
		crate_center = crate_node.global_position
	if bin_node:
		bin_center = bin_node.global_position

func _setup_button_detection() -> void:
	if button_area:
		button_area.area_entered.connect(_on_button_area_entered)
		button_area.body_entered.connect(_on_button_body_entered)

func _setup_barrier_detection() -> void:
	if barrier_area:
		barrier_area.body_entered.connect(_on_barrier_body_entered)

func _on_barrier_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("food_item"):
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func start_scene() -> void:
	super.start_scene()
	
	if sustainabot:
		sustainabot.set_skin_color(Color("#DDA63A"))  # Goal 2 yellow
	
	items_sorted = 0
	items_correct = 0
	conveyor_active = false
	_update_ui()
	
	await get_tree().create_timer(1.6).timeout
	
	_cache_container_positions()
	_connect_hand_signals()
	
	if progress_label:
		progress_label.text = "Touch the red button to start!"

func _connect_hand_signals() -> void:
	var hands = get_tree().get_nodes_in_group("xr_hand")
	for hand in hands:
		if hand.has_signal("object_released"):
			if not hand.object_released.is_connected(_on_object_released):
				hand.object_released.connect(_on_object_released)

	if xr_origin:
		for child_name in ["left", "right"]:
			var hand = xr_origin.get_node_or_null(child_name)
			if hand and hand.has_signal("object_released"):
				if not hand.object_released.is_connected(_on_object_released):
					hand.object_released.connect(_on_object_released)

func _is_hand_node(node: Node) -> bool:
	if not node:
		return false
	var name_lower = node.name.to_lower()
	if "hand" in name_lower or "left" in name_lower or "right" in name_lower:
		return true
	var parent = node.get_parent()
	if parent:
		var parent_name = parent.name.to_lower()
		if "hand" in parent_name or "left" in parent_name or "right" in parent_name:
			return true
	if node.is_in_group("xr_hand"):
		return true
	return false

func _on_button_area_entered(area: Area3D) -> void:
	if _button_cooldown > 0:
		return
	
	if _is_hand_node(area):
		_toggle_conveyor()
		_button_cooldown = 1.0
		_animate_button_press()

func _on_button_body_entered(body: Node3D) -> void:
	if _button_cooldown > 0:
		return
	
	if _is_hand_node(body):
		_toggle_conveyor()
		_button_cooldown = 1.0
		_animate_button_press()

func _toggle_conveyor() -> void:
	conveyor_active = not conveyor_active

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
		if items_sorted < TOTAL_ITEMS:
			await get_tree().create_timer(0.5).timeout
			if conveyor_active:
				_spawn_food_item()
	else:
		if progress_label:
			progress_label.text = "Conveyor stopped"

func _animate_button_press() -> void:
	if start_stop_button:
		var original_scale = start_stop_button.scale
		var tween = create_tween()
		tween.tween_property(start_stop_button, "scale", original_scale * 0.8, 0.1)
		tween.tween_property(start_stop_button, "scale", original_scale, 0.1)

func _spawn_food_item() -> void:
	if items_sorted >= TOTAL_ITEMS:
		return
	if not conveyor_active:
		return
	if food_items.size() >= 3:
		return

	var is_bad = randf() > 0.5
	var food_scene = bad_food_scene if is_bad else good_food_scene

	if food_scene == null:
		push_error("Goal 2: Food scene not loaded!")
		return

	var food_type_index = randi() % FOOD_MODELS.size()
	var food_name = FOOD_MODELS[food_type_index]

	print("Goal 2: Spawning %s food: %s" % ["bad" if is_bad else "good", food_name])

	var food_body = await _create_food_physics_body(food_scene, food_name, is_bad)

	if food_body:
		current_food_item = food_body
		food_items.append(food_body)

func _create_food_physics_body(food_scene: PackedScene, food_name: String, is_bad: bool) -> RigidBody3D:
	var temp_scene = food_scene.instantiate()

	var mesh_path = GLTF_PATH_PREFIX + food_name + "/" + food_name + "_streetFood_0"
	var mesh_node = temp_scene.get_node_or_null(mesh_path)

	if not mesh_node or not mesh_node is MeshInstance3D:
		mesh_node = _find_food_mesh_recursive(temp_scene, food_name)

	if not mesh_node:
		temp_scene.queue_free()
		push_warning("Goal 2: Could not find mesh for " + food_name)
		return null

	var rigid_body = RigidBody3D.new()
	rigid_body.name = food_name + "_Physics"
	rigid_body.collision_layer = 2
	rigid_body.collision_mask = 3  # Detect layers 1 (environment) AND 2 (other food)
	rigid_body.mass = 0.5
	rigid_body.linear_damp = 8.0
	rigid_body.angular_damp = 8.0
	rigid_body.freeze = false
	rigid_body.gravity_scale = 0.0

	rigid_body.set_meta("is_bad", is_bad)
	rigid_body.set_meta("food_name", food_name)
	rigid_body.add_to_group("food_item")

	var mesh_clone = mesh_node.duplicate() as MeshInstance3D
	mesh_clone.name = "FoodMesh"
	mesh_clone.transform = Transform3D.IDENTITY
	mesh_clone.scale = Vector3.ONE * 0.012
	rigid_body.add_child(mesh_clone)

	var col_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.08
	col_shape.shape = sphere
	rigid_body.add_child(col_shape)

	var detect_area = Area3D.new()
	detect_area.name = "HandDetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 1
	var detect_shape = CollisionShape3D.new()
	var detect_sphere = SphereShape3D.new()
	detect_sphere.radius = 0.2
	detect_shape.shape = detect_sphere
	detect_area.add_child(detect_shape)
	rigid_body.add_child(detect_area)

	detect_area.area_entered.connect(func(area): _on_food_area_entered(rigid_body, area))
	detect_area.area_exited.connect(func(area): _on_food_area_exited(rigid_body, area))

	get_tree().root.add_child(rigid_body)

	var spawn_pos = Vector3(0, 0.8, 0.3)  # Spawn above belt surface
	if spawn_point:
		spawn_pos = spawn_point.global_position
		spawn_pos.y = 0.8
	rigid_body.global_position = spawn_pos

	temp_scene.queue_free()

	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(rigid_body):
		rigid_body.gravity_scale = 1.0

	return rigid_body

func _find_food_mesh_recursive(node: Node, food_name: String) -> MeshInstance3D:
	if node.name.begins_with(food_name) and node is MeshInstance3D:
		return node
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

# Object released handler (kept for logging/future use - detection is now continuous)
func _on_object_released(object: RigidBody3D) -> void:
	if not object.is_in_group("food_item"):
		return
	print("Goal 2: Food released - continuous detection will handle it")

func _update_ui() -> void:
	if score_label:
		score_label.text = "Score: %d/%d" % [items_correct, TOTAL_ITEMS]
		var ratio = float(items_correct) / max(items_sorted, 1)
		if ratio >= 0.7:
			score_label.modulate = Color(0.2, 1, 0.2)
		elif ratio >= 0.5:
			score_label.modulate = Color(1, 1, 0.2)
		else:
			score_label.modulate = Color(1, 0.4, 0.4)

# CONTINUOUS CONTAINER DETECTION - checks every physics frame
func _check_food_in_containers() -> void:
	var items_to_process: Array = []

	for food in food_items:
		if not is_instance_valid(food):
			continue

		var food_pos = food.global_position

		# Check if inside crate bounds
		if crate_center != Vector3.ZERO:
			var dist_to_crate = food_pos.distance_to(crate_center)
			if dist_to_crate < CONTAINER_RADIUS:
				items_to_process.append({"food": food, "container": "crate"})
				continue

		# Check if inside bin bounds
		if bin_center != Vector3.ZERO:
			var dist_to_bin = food_pos.distance_to(bin_center)
			if dist_to_bin < CONTAINER_RADIUS:
				items_to_process.append({"food": food, "container": "bin"})
				continue

	# Process detected items (outside loop to avoid modifying array during iteration)
	for item in items_to_process:
		_process_sorted_food(item.food, item.container)

func _process_sorted_food(food: RigidBody3D, container: String) -> void:
	if not is_instance_valid(food):
		return

	var is_bad = food.get_meta("is_bad", false)
	var correct: bool = false

	if container == "crate":
		# Crate = good food should go here
		correct = not is_bad
	elif container == "bin":
		# Bin = bad food should go here
		correct = is_bad

	print("Goal 2: Food in %s, is_bad=%s, correct=%s" % [container, is_bad, correct])

	# Remove from tracking immediately
	food_items.erase(food)
	if food == current_food_item:
		current_food_item = null

	# Update score
	items_sorted += 1
	if correct:
		items_correct += 1
		if sustainabot:
			sustainabot.set_state("commending")
			var messages = ["Great sorting!", "Correct!", "Well done!", "Perfect!"]
			sustainabot.show_speech(messages[randi() % messages.size()], 1.5)
		report_action(true)
	else:
		if sustainabot:
			sustainabot.set_state("berating")
			var messages = ["Wrong bin!", "That's not right!", "Try again!"]
			sustainabot.show_speech(messages[randi() % messages.size()], 2.0)
		report_action(false)

	_update_ui()

	# Delete the food
	food.queue_free()

	# Check completion or spawn next
	if items_sorted >= TOTAL_ITEMS:
		_finish_task()
	elif conveyor_active:
		call_deferred("_spawn_food_item")

func _physics_process(delta: float) -> void:
	if not is_active:
		return

	if _button_cooldown > 0:
		_button_cooldown -= delta

	_apply_food_physics(delta)
	_check_food_in_containers()  # Continuous detection every frame
	_cleanup_fallen_items()

func _apply_food_physics(delta: float) -> void:
	for food in food_items:
		if is_instance_valid(food) and food.gravity_scale > 0:
			food.apply_central_force(Vector3(0, -9.8 * food.mass, 0))

			if conveyor_active and _is_on_conveyor_belt(food):
				var belt_direction = Vector3(0, 0, -1)
				var belt_force = belt_direction * belt_speed * 30.0 * food.mass
				food.apply_central_force(belt_force)

func _is_on_conveyor_belt(food: RigidBody3D) -> bool:
	var pos = food.global_position
	return pos.y < 1.0 and pos.y > 0.1 and abs(pos.x) < 0.5 and pos.z > -1.0 and pos.z < 0.5

func _cleanup_fallen_items() -> void:
	var items_to_remove: Array[RigidBody3D] = []

	for food in food_items:
		if is_instance_valid(food) and food.global_position.y < -2.0:
			items_to_remove.append(food)

	for food in items_to_remove:
		food_items.erase(food)
		if food == current_food_item:
			current_food_item = null
		food.queue_free()

	if items_to_remove.size() > 0 and conveyor_active and items_sorted < TOTAL_ITEMS:
		call_deferred("_spawn_food_item")

func _finish_task() -> void:
	conveyor_active = false

	var success_rate = float(items_correct) / float(TOTAL_ITEMS)
	var success = success_rate >= 0.7

	if sustainabot:
		if success:
			sustainabot.set_state("celebrating")
			sustainabot.show_speech("Great job! %d/%d correct!" % [items_correct, TOTAL_ITEMS], 4.0)
		else:
			sustainabot.set_state("berating")
			sustainabot.show_speech("Only %d/%d correct." % [items_correct, TOTAL_ITEMS], 4.0)

	if score_label:
		score_label.text = "Final: %d/%d" % [items_correct, TOTAL_ITEMS]

	if progress_label:
		progress_label.text = "Task Complete!"

	await get_tree().create_timer(4.0).timeout

	complete_task(success)

func end_scene() -> void:
	for food in food_items:
		if is_instance_valid(food):
			food.queue_free()
	food_items.clear()
	current_food_item = null
	conveyor_active = false

	super.end_scene()
