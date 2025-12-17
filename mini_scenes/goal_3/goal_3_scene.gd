extends MiniScene

# Constants
const WASH_DURATION: float = 20.0
const SUCCESS_THRESHOLD: float = 0.75
const SOAP_PARTICLE_LIFETIME: float = 2.0
const TAP_COOLDOWN: float = 0.5
const WATER_DETECTION_RADIUS: float = 0.2
const SOAP_CONTACT_RADIUS: float = 0.15
const WATER_FILL_RATE: float = 1.0 / 20.0  # Fill in 20 seconds
const WATER_DRAIN_RATE: float = 1.0 / 40.0  # Drain in 40 seconds
const SOAP_FILL_RATE: float = 1.0 / 10.0   # Fill in 10 seconds
const SOAP_DRAIN_RATE: float = 1.0 / 20.0  # Drain in 20 seconds

# Game state
enum GameState { INTRO, WAITING_FOR_TAP, WASHING, COMPLETE, FAILED }
var current_state: GameState = GameState.INTRO
var water_active: bool = false
var wash_timer: float = 0.0
var water_progress: float = 0.0
var soap_progress: float = 0.0
var both_above_threshold: bool = false

# Node references
var tap_area: Area3D = null
var water_detection_area: Area3D = null
var water_particles: GPUParticles3D = null
var soap_particles_left: GPUParticles3D = null
var soap_particles_right: GPUParticles3D = null
var water_progress_bar: Node3D = null
var soap_progress_bar: Node3D = null
var instruction_label: Label3D = null
var timer_label: Label3D = null
var soap_body: RigidBody3D = null
var sink_node: Node3D = null

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
var soap_held_by: Node3D = null  # Which hand is holding the soap
var _soap_original_freeze: bool = false
var _soap_original_gravity: float = 1.0

# Cooldowns
var _tap_cooldown: float = 0.0

# Cached positions
var water_area_center: Vector3 = Vector3.ZERO


func setup_scene() -> void:
	goal_number = 3
	print("Goal 3: setup_scene() starting...")

	_get_references()
	_setup_soap()
	_setup_tap_area()
	_setup_water_detection_area()
	_setup_water_particles()
	_setup_soap_particles()
	_setup_progress_bars()
	_setup_sink_collision()

	print("Goal 3: setup_scene() complete")


func _get_references() -> void:
	# Get sink
	if has_node("Sink"):
		sink_node = $Sink

	# Get XR references
	xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		left_hand = xr_origin.get_node_or_null("left")
		right_hand = xr_origin.get_node_or_null("right")


func _setup_soap() -> void:
	# The soap needs to be restructured - RigidBody3D as root
	# Remove existing broken soap structure
	if has_node("Soap"):
		var old_soap = $Soap
		old_soap.queue_free()

	# Create proper soap RigidBody3D with HEAVY physics (like Goal 2 food)
	soap_body = RigidBody3D.new()
	soap_body.name = "Soap"
	soap_body.collision_layer = 2
	soap_body.collision_mask = 3
	soap_body.mass = 0.5  # Heavier than before
	soap_body.linear_damp = 8.0  # High damping prevents bouncing
	soap_body.angular_damp = 8.0  # High angular damping prevents spinning
	soap_body.freeze = false
	soap_body.gravity_scale = 0.0  # Disabled until game starts
	soap_body.add_to_group("soap_item")  # For identification

	# Collision shape matching soap size
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.1, 0.03, 0.05)
	col.shape = box
	soap_body.add_child(col)

	# Yellow soap mesh
	var mesh = MeshInstance3D.new()
	mesh.name = "SoapMesh"
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.1, 0.03, 0.05)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.72, 0.08)
	box_mesh.material = mat
	mesh.mesh = box_mesh
	soap_body.add_child(mesh)

	# HandDetectArea for fist grab detection (NOT using pinch system)
	# This is just for detecting when hand is near soap
	var detect_area = Area3D.new()
	detect_area.name = "HandDetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 1
	var detect_shape = CollisionShape3D.new()
	var detect_sphere = SphereShape3D.new()
	detect_sphere.radius = 0.15  # Smaller radius for fist grab
	detect_shape.shape = detect_sphere
	detect_area.add_child(detect_shape)
	soap_body.add_child(detect_area)

	# NOTE: We do NOT connect to register_nearby_grabbable since soap uses fist, not pinch
	# The scene will handle fist detection directly

	# Position soap near sink (adjust based on sink position)
	soap_body.position = Vector3(-0.25, 0.65, 0.15)

	add_child(soap_body)
	print("Goal 3: Soap created with heavy physics (fist grab)")


# Fist grab handlers for soap
func _connect_fist_signals() -> void:
	# Connect to HandPoseDetector for fist detection on both hands
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
		return  # Already held

	if not soap_body or not is_instance_valid(soap_body):
		return

	# Check if hand is close enough to soap
	var dist = hand.global_position.distance_to(soap_body.global_position)
	if dist > 0.2:  # Must be within 20cm
		return

	# Grab the soap
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

	# Release soap with physics re-enabled
	soap_body.freeze = false
	soap_body.gravity_scale = 1.0
	soap_body.linear_velocity = Vector3(0, -0.3, 0)  # Gentle drop
	soap_body.angular_velocity = Vector3.ZERO

	print("Goal 3: Soap released by %s" % (soap_held_by.name if soap_held_by else "unknown"))
	soap_held_by = null


func _update_soap_position() -> void:
	# Move soap to hand position while held
	if soap_held_by and soap_body and is_instance_valid(soap_body):
		soap_body.global_position = soap_body.global_position.lerp(
			soap_held_by.global_position, 15.0 * get_physics_process_delta_time()
		)


func _setup_tap_area() -> void:
	tap_area = Area3D.new()
	tap_area.name = "TapArea"
	tap_area.collision_layer = 0
	tap_area.collision_mask = 1  # Detect hands

	var tap_shape = CollisionShape3D.new()
	var tap_box = BoxShape3D.new()
	tap_box.size = Vector3(0.12, 0.08, 0.12)
	tap_shape.shape = tap_box
	tap_area.add_child(tap_shape)

	# Position at tap handle (relative to sink, adjust as needed)
	# Sink is rotated 45 degrees, so adjust position accordingly
	tap_area.position = Vector3(0.15, 0.75, -0.15)

	tap_area.area_entered.connect(_on_tap_area_entered)
	add_child(tap_area)
	print("Goal 3: Tap area created")


func _on_tap_area_entered(area: Area3D) -> void:
	if _tap_cooldown > 0:
		return

	if _is_hand_node(area):
		_toggle_water()
		_tap_cooldown = TAP_COOLDOWN


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


func _toggle_water() -> void:
	water_active = not water_active

	if water_particles:
		water_particles.emitting = water_active

	if sustainabot:
		if water_active:
			sustainabot.show_speech("Water on! Place hands under tap.", 2.0)
		else:
			sustainabot.show_speech("Water off.", 1.5)

	# Start washing state when water first turned on
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
	water_box.size = Vector3(0.3, 0.15, 0.25)
	water_shape.shape = water_box
	water_detection_area.add_child(water_shape)

	# Position under tap spout, in sink basin
	water_detection_area.position = Vector3(0, 0.45, 0)

	add_child(water_detection_area)
	print("Goal 3: Water detection area created")


func _setup_water_particles() -> void:
	water_particles = GPUParticles3D.new()
	water_particles.name = "WaterParticles"
	water_particles.emitting = false
	water_particles.amount = 40
	water_particles.lifetime = 0.6
	water_particles.one_shot = false
	water_particles.explosiveness = 0.0

	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 8.0
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 1.8
	mat.gravity = Vector3(0, -8, 0)
	mat.color = Color(0.3, 0.6, 0.95, 0.8)
	water_particles.process_material = mat

	# Water droplet mesh
	var mesh = SphereMesh.new()
	mesh.radius = 0.012
	mesh.height = 0.024
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.3, 0.6, 0.95, 0.7)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat
	water_particles.draw_pass_1 = mesh

	# Position at tap spout
	water_particles.position = Vector3(0.05, 0.7, -0.05)

	add_child(water_particles)
	print("Goal 3: Water particles created")


func _setup_soap_particles() -> void:
	# Create soap particles for left hand
	soap_particles_left = _create_soap_particle_system()
	soap_particles_left.name = "SoapParticlesLeft"
	add_child(soap_particles_left)

	# Create soap particles for right hand
	soap_particles_right = _create_soap_particle_system()
	soap_particles_right.name = "SoapParticlesRight"
	add_child(soap_particles_right)

	print("Goal 3: Soap particles created for both hands")


func _create_soap_particle_system() -> GPUParticles3D:
	var particles = GPUParticles3D.new()
	particles.emitting = false
	particles.amount = 25
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

	# Yellow soap color with fade out
	mat.color = Color(1.0, 0.9, 0.3, 1.0)

	# Color gradient for fade out
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 0.9, 0.3, 1.0))
	gradient.set_color(1, Color(1.0, 0.9, 0.3, 0.0))
	var color_tex = GradientTexture1D.new()
	color_tex.gradient = gradient
	mat.color_ramp = color_tex

	particles.process_material = mat

	# Small bubble mesh
	var mesh = SphereMesh.new()
	mesh.radius = 0.008
	mesh.height = 0.016
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(1.0, 0.9, 0.3, 0.9)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh

	return particles


func _setup_progress_bars() -> void:
	var ui_container = Node3D.new()
	ui_container.name = "UI"
	ui_container.position = Vector3(0, 1.3, -0.4)
	add_child(ui_container)

	# Instruction label at top
	instruction_label = Label3D.new()
	instruction_label.name = "InstructionLabel"
	instruction_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	instruction_label.font_size = 48
	instruction_label.outline_size = 8
	instruction_label.position = Vector3(0, 0.35, 0)
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.text = "Wash your hands!"
	ui_container.add_child(instruction_label)

	# Timer label
	timer_label = Label3D.new()
	timer_label.name = "TimerLabel"
	timer_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	timer_label.font_size = 36
	timer_label.outline_size = 6
	timer_label.position = Vector3(0, 0.22, 0)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.text = ""
	timer_label.modulate = Color.WHITE
	ui_container.add_child(timer_label)

	# Water progress bar (blue) - top bar
	water_progress_bar = _create_progress_bar(Color(0.2, 0.5, 0.9), "Water")
	water_progress_bar.position = Vector3(0, 0.08, 0)
	ui_container.add_child(water_progress_bar)

	# Soap progress bar (yellow) - bottom bar
	soap_progress_bar = _create_progress_bar(Color(1.0, 0.85, 0.2), "Soap")
	soap_progress_bar.position = Vector3(0, -0.08, 0)
	ui_container.add_child(soap_progress_bar)

	print("Goal 3: Progress bars created")


func _create_progress_bar(color: Color, label_text: String) -> Node3D:
	var bar_container = Node3D.new()
	bar_container.name = label_text + "ProgressBar"

	# Background (dark gray)
	var bg = MeshInstance3D.new()
	bg.name = "Background"
	var bg_mesh = BoxMesh.new()
	bg_mesh.size = Vector3(0.5, 0.04, 0.015)
	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.2, 0.2, 0.2)
	bg_mesh.material = bg_mat
	bg.mesh = bg_mesh
	bar_container.add_child(bg)

	# Fill (colored)
	var fill = MeshInstance3D.new()
	fill.name = "Fill"
	var fill_mesh = BoxMesh.new()
	fill_mesh.size = Vector3(0.48, 0.035, 0.02)
	var fill_mat = StandardMaterial3D.new()
	fill_mat.albedo_color = color
	fill_mat.emission_enabled = true
	fill_mat.emission = color * 0.4
	fill_mesh.material = fill_mat
	fill.mesh = fill_mesh
	fill.position = Vector3(-0.24, 0, 0.005)
	fill.scale.x = 0.01  # Start nearly empty
	bar_container.add_child(fill)

	# Threshold line at 75%
	var threshold = MeshInstance3D.new()
	threshold.name = "Threshold"
	var threshold_mesh = BoxMesh.new()
	threshold_mesh.size = Vector3(0.006, 0.055, 0.025)
	var threshold_mat = StandardMaterial3D.new()
	threshold_mat.albedo_color = Color.WHITE
	threshold_mat.emission_enabled = true
	threshold_mat.emission = Color.WHITE * 0.3
	threshold_mesh.material = threshold_mat
	threshold.mesh = threshold_mesh
	threshold.position = Vector3(0.115, 0, 0.01)  # 75% position
	bar_container.add_child(threshold)

	# Label
	var label = Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = label_text
	label.font_size = 24
	label.outline_size = 4
	label.position = Vector3(-0.32, 0, 0)
	bar_container.add_child(label)

	return bar_container


func _update_progress_bar(bar: Node3D, progress: float) -> void:
	if not bar:
		return
	var fill = bar.get_node_or_null("Fill") as MeshInstance3D
	if fill:
		var clamped = clamp(progress, 0.01, 1.0)
		fill.scale.x = clamped
		fill.position.x = -0.24 + (0.24 * clamped)


func _setup_sink_collision() -> void:
	# Add collision to sink basin so particles don't fall through
	var sink_collision = StaticBody3D.new()
	sink_collision.name = "SinkBasinCollision"
	sink_collision.collision_layer = 1
	sink_collision.collision_mask = 0

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.4, 0.05, 0.35)
	col_shape.shape = box
	sink_collision.add_child(col_shape)

	# Position at bottom of sink basin
	sink_collision.position = Vector3(0, 0.35, 0)

	add_child(sink_collision)
	print("Goal 3: Sink basin collision created")


func start_scene() -> void:
	super.start_scene()

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

	await get_tree().create_timer(1.6).timeout

	# Get XR references and connect fist signals
	_get_xr_references()
	_connect_fist_signals()

	# Cache water detection area position
	if water_detection_area:
		water_area_center = water_detection_area.global_position

	# Enable soap physics
	if soap_body:
		soap_body.gravity_scale = 1.0

	# Transition to waiting state
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

	# Update cooldowns
	if _tap_cooldown > 0:
		_tap_cooldown -= delta

	# Update XR hand references if needed
	if not left_hand or not right_hand:
		_get_xr_references()
		_connect_fist_signals()

	# Update soap position if held (fist grab)
	_update_soap_position()

	# Run detection and game logic
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

	# Update cached position if needed
	if water_detection_area:
		water_area_center = water_detection_area.global_position

	if water_area_center == Vector3.ZERO:
		return

	if left_hand and is_instance_valid(left_hand):
		var dist = left_hand.global_position.distance_to(water_area_center)
		if dist < WATER_DETECTION_RADIUS:
			left_hand_in_water = true

	if right_hand and is_instance_valid(right_hand):
		var dist = right_hand.global_position.distance_to(water_area_center)
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
	# Update left hand soap particles
	if soap_particles_left:
		if left_hand and is_instance_valid(left_hand):
			soap_particles_left.global_position = left_hand.global_position
		soap_particles_left.emitting = soap_touching_left

	# Update right hand soap particles
	if soap_particles_right:
		if right_hand and is_instance_valid(right_hand):
			soap_particles_right.global_position = right_hand.global_position
		soap_particles_right.emitting = soap_touching_right


func _update_progress(delta: float) -> void:
	if current_state != GameState.WASHING:
		return

	var hands_in_water = left_hand_in_water or right_hand_in_water
	var soap_active = soap_touching_left or soap_touching_right

	# Water progress - fills while hands are under water
	if hands_in_water and water_active:
		water_progress = min(water_progress + delta * WATER_FILL_RATE, 1.0)
	else:
		water_progress = max(water_progress - delta * WATER_DRAIN_RATE, 0.0)

	# Soap progress - fills while soap contacts hands
	if soap_active:
		soap_progress = min(soap_progress + delta * SOAP_FILL_RATE, 1.0)
	else:
		soap_progress = max(soap_progress - delta * SOAP_DRAIN_RATE, 0.0)

	# Update visual progress bars
	_update_progress_bar(water_progress_bar, water_progress)
	_update_progress_bar(soap_progress_bar, soap_progress)

	# Check if both are above threshold
	var currently_above = water_progress >= SUCCESS_THRESHOLD and soap_progress >= SUCCESS_THRESHOLD

	if currently_above:
		if not both_above_threshold:
			# Just crossed threshold - start timer
			both_above_threshold = true
			wash_timer = 0.0
			if sustainabot:
				sustainabot.set_state("commending")
				sustainabot.show_speech("Keep it up!", 2.0)

		# Increment wash timer
		wash_timer += delta

		# Update timer display
		var remaining = WASH_DURATION - wash_timer
		if timer_label:
			timer_label.text = "%.1fs remaining" % max(remaining, 0)
			timer_label.modulate = Color.GREEN

		# Check for completion
		if wash_timer >= WASH_DURATION:
			_complete_washing(true)
	else:
		if both_above_threshold:
			# Dropped below threshold - reset timer
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

	# Stop water
	water_active = false
	if water_particles:
		water_particles.emitting = false

	# Stop soap particles
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
	# Clean up
	water_active = false
	if water_particles:
		water_particles.emitting = false
	if soap_particles_left:
		soap_particles_left.emitting = false
	if soap_particles_right:
		soap_particles_right.emitting = false

	super.end_scene()
