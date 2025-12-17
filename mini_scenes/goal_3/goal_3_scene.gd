extends MiniScene

# Constants
const WASH_DURATION: float = 20.0
const SUCCESS_THRESHOLD: float = 0.75
const SOAP_PARTICLE_LIFETIME: float = 2.0
const TAP_COOLDOWN: float = 0.5
const WATER_DETECTION_RADIUS: float = 0.35  # Increased from 0.2 for better detection
const SOAP_CONTACT_RADIUS: float = 0.20     # Increased from 0.15
const WATER_FILL_RATE: float = 1.0 / 20.0   # Fill in 20 seconds
const WATER_DRAIN_RATE: float = 1.0 / 40.0  # Drain in 40 seconds
const SOAP_FILL_RATE: float = 1.0 / 10.0    # Fill in 10 seconds
const SOAP_DRAIN_RATE: float = 1.0 / 20.0   # Drain in 20 seconds

# Game state
enum GameState { INTRO, WAITING_FOR_TAP, WASHING, COMPLETE, FAILED }
var current_state: GameState = GameState.INTRO
var water_active: bool = false
var wash_timer: float = 0.0
var water_progress: float = 0.0
var soap_progress: float = 0.0
var both_above_threshold: bool = false

# Node references - from scene
var soap_body: RigidBody3D = null
var sink_node: Node3D = null
var instruction_label: Label3D = null
var timer_label: Label3D = null
var water_progress_bar: Node3D = null
var soap_progress_bar: Node3D = null

# Marker references - for positioning
var water_spout_marker: Marker3D = null
var water_zone_marker: Marker3D = null

# Scene-defined nodes
var tap_area: Area3D = null

# Created at runtime
var water_detection_area: Area3D = null
var water_particles: GPUParticles3D = null
var soap_particles_left: GPUParticles3D = null
var soap_particles_right: GPUParticles3D = null

# Detection state
var left_hand_in_water: bool = false
var right_hand_in_water: bool = false
var soap_touching_left: bool = false
var soap_touching_right: bool = false

# XR references
var xr_origin: XROrigin3D = null
var left_hand: Node3D = null
var right_hand: Node3D = null

# Fist grab state (soap uses fist instead of pinch)
var left_fisting: bool = false
var right_fisting: bool = false
var soap_held_by: Node3D = null
var _soap_original_freeze: bool = false
var _soap_original_gravity: float = 1.0

# Cooldowns
var _tap_cooldown: float = 0.0

# Cached positions
var water_zone_center: Vector3 = Vector3.ZERO


func setup_scene() -> void:
	goal_number = 3
	print("Goal 3: setup_scene() starting...")

	_get_references()
	_connect_tap_area()  # Use signals like Goal 1
	_setup_water_detection_area()
	_setup_water_particles()
	_setup_soap_particles()
	_setup_sink_collision()

	print("Goal 3: setup_scene() complete")


func _get_references() -> void:
	# Get sink
	if has_node("Sink"):
		sink_node = $Sink

	# Get markers for positioning
	if has_node("Markers/WaterSpout"):
		water_spout_marker = $Markers/WaterSpout
	if has_node("Markers/WaterZone"):
		water_zone_marker = $Markers/WaterZone

	# Get tap area from scene (like Goal 1 does with pump_handle)
	if has_node("TapArea"):
		tap_area = $TapArea
		print("Goal 3: Found TapArea in scene")

	# Get soap from scene (not creating dynamically anymore)
	if has_node("Soap"):
		soap_body = $Soap
		soap_body.add_to_group("soap_item")
		soap_body.gravity_scale = 0.0  # Disabled until game starts
		print("Goal 3: Found Soap in scene")
	else:
		print("Goal 3: ERROR - Soap node not found in scene!")

	# Get UI elements from scene
	if has_node("UI/InstructionLabel"):
		instruction_label = $UI/InstructionLabel
	if has_node("UI/TimerLabel"):
		timer_label = $UI/TimerLabel
	if has_node("UI/WaterProgressBar"):
		water_progress_bar = $UI/WaterProgressBar
	if has_node("UI/SoapProgressBar"):
		soap_progress_bar = $UI/SoapProgressBar

	# Get XR references
	xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		left_hand = xr_origin.get_node_or_null("left")
		right_hand = xr_origin.get_node_or_null("right")


# Fist grab handlers for soap
func _connect_fist_signals() -> void:
	if left_hand and left_hand.has_node("HandPoseDetector"):
		var detector = left_hand.get_node("HandPoseDetector")
		if not detector.pose_started.is_connected(_on_left_hand_pose_started):
			detector.pose_started.connect(_on_left_hand_pose_started)
		if not detector.pose_ended.is_connected(_on_left_hand_pose_ended):
			detector.pose_ended.connect(_on_left_hand_pose_ended)
		print("Goal 3: Connected left hand fist detection")

	if right_hand and right_hand.has_node("HandPoseDetector"):
		var detector = right_hand.get_node("HandPoseDetector")
		if not detector.pose_started.is_connected(_on_right_hand_pose_started):
			detector.pose_started.connect(_on_right_hand_pose_started)
		if not detector.pose_ended.is_connected(_on_right_hand_pose_ended):
			detector.pose_ended.connect(_on_right_hand_pose_ended)
		print("Goal 3: Connected right hand fist detection")


func _on_left_hand_pose_started(pose_name: String) -> void:
	if pose_name == "Fist":
		left_fisting = true
		_try_grab_soap(left_hand)


func _on_left_hand_pose_ended(pose_name: String) -> void:
	if pose_name == "Fist":
		left_fisting = false
		if soap_held_by == left_hand:
			_release_soap()


func _on_right_hand_pose_started(pose_name: String) -> void:
	if pose_name == "Fist":
		right_fisting = true
		_try_grab_soap(right_hand)


func _on_right_hand_pose_ended(pose_name: String) -> void:
	if pose_name == "Fist":
		right_fisting = false
		if soap_held_by == right_hand:
			_release_soap()


func _try_grab_soap(hand: Node3D) -> void:
	if soap_held_by != null:
		return

	if not soap_body or not is_instance_valid(soap_body):
		return

	var dist = hand.global_position.distance_to(soap_body.global_position)
	if dist > 0.25:  # Must be within 25cm
		return

	_soap_original_freeze = soap_body.freeze
	_soap_original_gravity = soap_body.gravity_scale

	soap_body.freeze = true
	soap_body.linear_velocity = Vector3.ZERO
	soap_body.angular_velocity = Vector3.ZERO

	soap_held_by = hand
	print("Goal 3: Soap grabbed by %s" % hand.name)


func _release_soap() -> void:
	if not soap_body or not is_instance_valid(soap_body):
		soap_held_by = null
		return

	soap_body.freeze = false
	soap_body.gravity_scale = 1.0
	soap_body.linear_velocity = Vector3(0, -0.3, 0)
	soap_body.angular_velocity = Vector3.ZERO

	print("Goal 3: Soap released by %s" % (soap_held_by.name if soap_held_by else "unknown"))
	soap_held_by = null


func _update_soap_position() -> void:
	if soap_held_by and soap_body and is_instance_valid(soap_body):
		soap_body.global_position = soap_body.global_position.lerp(
			soap_held_by.global_position, 15.0 * get_physics_process_delta_time()
		)


# Connect tap area signals (like Goal 1 does with pump_handle)
func _connect_tap_area() -> void:
	if tap_area:
		tap_area.area_entered.connect(_on_tap_area_entered)
		tap_area.area_exited.connect(_on_tap_area_exited)
		print("Goal 3: Tap area signals connected")
	else:
		push_warning("Goal 3: TapArea not found in scene!")


func _on_tap_area_entered(area: Area3D) -> void:
	if _is_hand_area(area) and _tap_cooldown <= 0:
		if current_state != GameState.INTRO:
			_toggle_water()
			_tap_cooldown = TAP_COOLDOWN
			print("Goal 3: Tap activated by %s" % area.name)


func _on_tap_area_exited(_area: Area3D) -> void:
	pass  # Water stays on/off until tapped again


func _is_hand_area(area: Area3D) -> bool:
	var name_lower = area.name.to_lower()
	var parent_name = area.get_parent().name.to_lower() if area.get_parent() else ""
	return "hand" in name_lower or "hand" in parent_name


func _toggle_water() -> void:
	water_active = not water_active

	if water_particles:
		water_particles.emitting = water_active

	if sustainabot:
		if water_active:
			sustainabot.show_speech("Water on! Place hands under tap.", 2.0)
		else:
			sustainabot.show_speech("Water off.", 1.5)

	if water_active and current_state == GameState.WAITING_FOR_TAP:
		current_state = GameState.WASHING
		_update_instruction_text()

	print("Goal 3: Water toggled - active: %s" % water_active)


func _setup_water_detection_area() -> void:
	water_detection_area = Area3D.new()
	water_detection_area.name = "WaterDetectionArea"
	water_detection_area.collision_layer = 0
	water_detection_area.collision_mask = 1

	var water_shape = CollisionShape3D.new()
	var water_box = BoxShape3D.new()
	water_box.size = Vector3(0.35, 0.2, 0.3)  # Larger detection zone
	water_shape.shape = water_box
	water_detection_area.add_child(water_shape)

	# Add as child of WaterZone marker (inherits position automatically)
	if water_zone_marker:
		water_zone_marker.add_child(water_detection_area)
		print("Goal 3: Water detection area added as child of WaterZone marker")
	else:
		add_child(water_detection_area)
		water_detection_area.position = Vector3(-0.1, 0.58, -0.26)  # Fallback
		print("Goal 3: Water detection area using fallback position")


func _setup_water_particles() -> void:
	water_particles = GPUParticles3D.new()
	water_particles.name = "WaterParticles"
	water_particles.emitting = false
	water_particles.amount = 50
	water_particles.lifetime = 0.8
	water_particles.one_shot = false
	water_particles.explosiveness = 0.0

	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 10.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, -10, 0)
	mat.color = Color(0.3, 0.6, 0.95, 0.8)
	water_particles.process_material = mat

	var mesh = SphereMesh.new()
	mesh.radius = 0.015
	mesh.height = 0.03
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.3, 0.6, 0.95, 0.7)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat
	water_particles.draw_pass_1 = mesh

	# Add as child of WaterSpout marker (like Goal 1 does)
	# This way particles inherit the marker's position automatically
	if water_spout_marker:
		water_spout_marker.add_child(water_particles)
		print("Goal 3: Water particles added as child of WaterSpout marker")
	else:
		add_child(water_particles)
		water_particles.position = Vector3(-0.08, 0.66, -0.22)  # Fallback
		print("Goal 3: Water particles using fallback position")


func _setup_soap_particles() -> void:
	soap_particles_left = _create_soap_particle_system()
	soap_particles_left.name = "SoapParticlesLeft"
	add_child(soap_particles_left)

	soap_particles_right = _create_soap_particle_system()
	soap_particles_right.name = "SoapParticlesRight"
	add_child(soap_particles_right)

	print("Goal 3: Soap particles created for both hands")


func _create_soap_particle_system() -> GPUParticles3D:
	var particles = GPUParticles3D.new()
	particles.emitting = false
	particles.amount = 30
	particles.lifetime = SOAP_PARTICLE_LIFETIME
	particles.one_shot = false
	particles.explosiveness = 0.2

	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.3, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.03
	mat.initial_velocity_max = 0.1
	mat.gravity = Vector3(0, -0.3, 0)
	mat.damping_min = 3.0
	mat.damping_max = 5.0

	mat.color = Color(1.0, 0.9, 0.3, 1.0)

	var gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 0.9, 0.3, 1.0))
	gradient.set_color(1, Color(1.0, 0.9, 0.3, 0.0))
	var color_tex = GradientTexture1D.new()
	color_tex.gradient = gradient
	mat.color_ramp = color_tex

	particles.process_material = mat

	var mesh = SphereMesh.new()
	mesh.radius = 0.01
	mesh.height = 0.02
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(1.0, 0.9, 0.3, 0.9)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh

	return particles


func _update_progress_bar(bar: Node3D, progress: float) -> void:
	if not bar:
		return
	var fill = bar.get_node_or_null("Fill") as MeshInstance3D
	if fill:
		var clamped = clamp(progress, 0.01, 1.0)
		fill.scale.x = clamped
		fill.position.x = -0.24 + (0.24 * clamped)


func _setup_sink_collision() -> void:
	var sink_collision = StaticBody3D.new()
	sink_collision.name = "SinkBasinCollision"
	sink_collision.collision_layer = 1
	sink_collision.collision_mask = 0

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.5, 0.05, 0.4)
	col_shape.shape = box
	sink_collision.add_child(col_shape)

	# Add to scene first - position will be set in _position_from_markers()
	add_child(sink_collision)


# Log positions for debugging
func _log_positions() -> void:
	print("Goal 3: Positions - Tap: %s, Soap: %s" % [
		tap_area.global_position if tap_area else "N/A",
		soap_body.global_position if soap_body else "N/A"
	])


func start_scene() -> void:
	super.start_scene()

	# Set Sustainabot skin color to Goal 3 green (Good Health)
	if sustainabot:
		sustainabot.set_skin_color(Color("#4C9F38"))

	current_state = GameState.INTRO
	water_progress = 0.0
	soap_progress = 0.0
	wash_timer = 0.0
	water_active = false
	both_above_threshold = false
	soap_held_by = null
	left_fisting = false
	right_fisting = false

	_update_progress_bar(water_progress_bar, 0.0)
	_update_progress_bar(soap_progress_bar, 0.0)

	if water_particles:
		water_particles.emitting = false

	# Wait for fade-in tween to restore scale, then log positions for debugging
	# (Nodes are now children of markers, so positions are automatic)
	await get_tree().create_timer(0.2).timeout
	_log_positions()

	await get_tree().create_timer(1.4).timeout

	# Get XR references and connect fist signals
	_get_xr_references()
	_connect_fist_signals()

	# Enable soap physics
	if soap_body:
		soap_body.gravity_scale = 1.0

	current_state = GameState.WAITING_FOR_TAP

	if instruction_label:
		instruction_label.text = "Touch the tap to turn on water"

	if sustainabot:
		sustainabot.set_state("instructing")
		sustainabot.show_speech("Time to wash your hands!\nTouch the tap to start.", 4.0)

	print("Goal 3: Scene started, waiting for tap activation")


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	if _tap_cooldown > 0:
		_tap_cooldown -= delta

	if not left_hand or not right_hand:
		_get_xr_references()
		_connect_fist_signals()

	_update_soap_position()
	_check_hands_in_water()
	_check_soap_contact()
	_update_soap_particles()
	_update_progress(delta)


func _get_xr_references() -> void:
	if not xr_origin:
		xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		if not left_hand:
			left_hand = xr_origin.get_node_or_null("left")
		if not right_hand:
			right_hand = xr_origin.get_node_or_null("right")


func _check_hands_in_water() -> void:
	left_hand_in_water = false
	right_hand_in_water = false

	if not water_active:
		return

	# Use water_detection_area position (child of marker, so position is correct)
	if not water_detection_area:
		return

	var check_center = water_detection_area.global_position

	# Skip if position is still at origin (scene not fully loaded)
	if check_center == Vector3.ZERO:
		return

	if left_hand and is_instance_valid(left_hand):
		var dist = left_hand.global_position.distance_to(check_center)
		if dist < WATER_DETECTION_RADIUS:
			left_hand_in_water = true

	if right_hand and is_instance_valid(right_hand):
		var dist = right_hand.global_position.distance_to(check_center)
		if dist < WATER_DETECTION_RADIUS:
			right_hand_in_water = true


func _check_soap_contact() -> void:
	soap_touching_left = false
	soap_touching_right = false

	if not soap_body or not is_instance_valid(soap_body):
		return

	var soap_pos = soap_body.global_position

	if left_hand and is_instance_valid(left_hand):
		var dist = left_hand.global_position.distance_to(soap_pos)
		if dist < SOAP_CONTACT_RADIUS:
			soap_touching_left = true

	if right_hand and is_instance_valid(right_hand):
		var dist = right_hand.global_position.distance_to(soap_pos)
		if dist < SOAP_CONTACT_RADIUS:
			soap_touching_right = true


func _update_soap_particles() -> void:
	if soap_particles_left:
		if left_hand and is_instance_valid(left_hand):
			soap_particles_left.global_position = left_hand.global_position
		soap_particles_left.emitting = soap_touching_left

	if soap_particles_right:
		if right_hand and is_instance_valid(right_hand):
			soap_particles_right.global_position = right_hand.global_position
		soap_particles_right.emitting = soap_touching_right


func _update_progress(delta: float) -> void:
	if current_state != GameState.WASHING:
		return

	var hands_in_water = left_hand_in_water or right_hand_in_water
	var soap_active = soap_touching_left or soap_touching_right

	if hands_in_water and water_active:
		water_progress = min(water_progress + delta * WATER_FILL_RATE, 1.0)
	else:
		water_progress = max(water_progress - delta * WATER_DRAIN_RATE, 0.0)

	if soap_active:
		soap_progress = min(soap_progress + delta * SOAP_FILL_RATE, 1.0)
	else:
		soap_progress = max(soap_progress - delta * SOAP_DRAIN_RATE, 0.0)

	_update_progress_bar(water_progress_bar, water_progress)
	_update_progress_bar(soap_progress_bar, soap_progress)

	var currently_above = water_progress >= SUCCESS_THRESHOLD and soap_progress >= SUCCESS_THRESHOLD

	if currently_above:
		if not both_above_threshold:
			both_above_threshold = true
			wash_timer = 0.0
			if sustainabot:
				sustainabot.set_state("commending")
				sustainabot.show_speech("Keep it up!", 2.0)

		wash_timer += delta

		var remaining = WASH_DURATION - wash_timer
		if timer_label:
			timer_label.text = "%.1fs remaining" % max(remaining, 0)
			timer_label.modulate = Color.GREEN

		if wash_timer >= WASH_DURATION:
			_complete_washing(true)
	else:
		if both_above_threshold:
			both_above_threshold = false
			wash_timer = 0.0
			if timer_label:
				timer_label.text = "Keep both bars above 75%!"
				timer_label.modulate = Color.YELLOW
			if sustainabot:
				sustainabot.set_state("instructing")
				sustainabot.show_speech("Keep scrubbing!", 1.5)

	_update_instruction_text()


func _update_instruction_text() -> void:
	if not instruction_label:
		return

	if current_state == GameState.WAITING_FOR_TAP:
		instruction_label.text = "Touch the tap to turn on water"
	elif current_state == GameState.WASHING:
		if not water_active:
			instruction_label.text = "Turn on the water!"
		elif water_progress < SUCCESS_THRESHOLD and soap_progress < SUCCESS_THRESHOLD:
			instruction_label.text = "Rinse hands & apply soap"
		elif water_progress < SUCCESS_THRESHOLD:
			instruction_label.text = "Keep rinsing! (%.0f%%)" % (water_progress * 100)
		elif soap_progress < SUCCESS_THRESHOLD:
			instruction_label.text = "Apply more soap! (%.0f%%)" % (soap_progress * 100)
		elif both_above_threshold:
			instruction_label.text = "Excellent! Keep washing!"
		else:
			instruction_label.text = "Keep both bars above 75%!"


func _complete_washing(success: bool) -> void:
	if current_state == GameState.COMPLETE or current_state == GameState.FAILED:
		return

	current_state = GameState.COMPLETE if success else GameState.FAILED

	water_active = false
	if water_particles:
		water_particles.emitting = false

	if soap_particles_left:
		soap_particles_left.emitting = false
	if soap_particles_right:
		soap_particles_right.emitting = false

	if sustainabot:
		if success:
			sustainabot.set_state("celebrating")
			sustainabot.show_speech("Great job!\nClean hands help\nprevent disease!", 4.0)
		else:
			sustainabot.set_state("berating")
			sustainabot.show_speech("Not quite clean enough.\nTry again!", 3.0)

	if instruction_label:
		instruction_label.text = "Hands Clean!" if success else "Try again!"
		instruction_label.modulate = Color.GREEN if success else Color.RED

	if timer_label:
		timer_label.text = "Complete!" if success else "Failed"
		timer_label.modulate = Color.GREEN if success else Color.RED

	print("Goal 3: Washing complete - success: %s" % success)

	await get_tree().create_timer(4.0).timeout
	complete_task(success)


func end_scene() -> void:
	water_active = false
	if water_particles:
		water_particles.emitting = false
	if soap_particles_left:
		soap_particles_left.emitting = false
	if soap_particles_right:
		soap_particles_right.emitting = false

	super.end_scene()
