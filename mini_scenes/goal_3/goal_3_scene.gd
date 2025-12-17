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
		# Freeze soap until scene is ready (prevents falling through during fade-in)
		soap_body.freeze = true
		# Ensure soap has proper physics properties
		if soap_body.mass < 0.1:
			soap_body.mass = 0.5
		soap_body.gravity_scale = 1.0  # Will be overridden by manual gravity, but good to set
		print("Goal 3: Found Soap in scene at %s (mass=%.2f)" % [soap_body.position, soap_body.mass])
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
	if left_hand and is_instance_valid(left_hand):
		if left_hand.has_node("HandPoseDetector"):
			var detector = left_hand.get_node("HandPoseDetector")
			if detector and not detector.pose_started.is_connected(_on_left_hand_pose_started):
				detector.pose_started.connect(_on_left_hand_pose_started)
				detector.pose_ended.connect(_on_left_hand_pose_ended)
				print("Goal 3: Connected left hand fist detection")
		# Also connect area signals for the hand's collision area (fallback if no pose detector)
		if left_hand.has_node("hand_area"):
			var hand_area = left_hand.get_node("hand_area")
			if hand_area is Area3D and soap_body and soap_body.has_node("HandDetectArea"):
				var soap_detect_area = soap_body.get_node("HandDetectArea")
				if not hand_area.area_entered.is_connected(_on_hand_near_soap):
					hand_area.area_entered.connect(_on_hand_near_soap.bind("left"))
					print("Goal 3: Connected left hand area detection")

	if right_hand and is_instance_valid(right_hand):
		if right_hand.has_node("HandPoseDetector"):
			var detector = right_hand.get_node("HandPoseDetector")
			if detector and not detector.pose_started.is_connected(_on_right_hand_pose_started):
				detector.pose_started.connect(_on_right_hand_pose_started)
				detector.pose_ended.connect(_on_right_hand_pose_ended)
				print("Goal 3: Connected right hand fist detection")
		# Also connect area signals for the hand's collision area (fallback)
		if right_hand.has_node("hand_area"):
			var hand_area = right_hand.get_node("hand_area")
			if hand_area is Area3D and soap_body and soap_body.has_node("HandDetectArea"):
				var soap_detect_area = soap_body.get_node("HandDetectArea")
				if not hand_area.area_entered.is_connected(_on_hand_near_soap):
					hand_area.area_entered.connect(_on_hand_near_soap.bind("right"))
					print("Goal 3: Connected right hand area detection")


func _on_hand_near_soap(area: Area3D, hand_name: String) -> void:
	# Fallback grab mechanism when hand enters soap detection area
	if area == soap_body.get_node_or_null("HandDetectArea"):
		var hand = left_hand if hand_name == "left" else right_hand
		if hand and not soap_held_by:
			_try_grab_soap(hand)
			print("Goal 3: Soap auto-grabbed by %s (area detection)" % hand_name)


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
	if not hand or not is_instance_valid(hand):
		return
		
	if soap_held_by != null:
		return

	if not soap_body or not is_instance_valid(soap_body):
		return

	var dist = hand.global_position.distance_to(soap_body.global_position)
	if dist > 0.3:  # Must be within 30cm (increased for easier grabbing)
		return

	_soap_original_freeze = soap_body.freeze
	_soap_original_gravity = soap_body.gravity_scale

	soap_body.freeze = true
	soap_body.linear_velocity = Vector3.ZERO
	soap_body.angular_velocity = Vector3.ZERO

	soap_held_by = hand
	print("Goal 3: Soap grabbed by %s (distance: %.2fcm)" % [hand.name, dist * 100])


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


func _check_proximity_grab() -> void:
	# Auto-grab soap when hand gets very close (fallback if pose detection fails)
	const GRAB_DISTANCE = 0.15  # 15cm auto-grab radius
	const RELEASE_DISTANCE = 0.5  # 50cm release distance
	
	if not soap_body or not is_instance_valid(soap_body):
		return
	
	# Account for scene scale
	var scaled_grab = GRAB_DISTANCE * scale.x
	var scaled_release = RELEASE_DISTANCE * scale.x
	
	# Check if currently held soap should be released (hand moved too far)
	if soap_held_by and is_instance_valid(soap_held_by):
		var dist_to_holder = soap_held_by.global_position.distance_to(soap_body.global_position)
		if dist_to_holder > scaled_release:
			print("Goal 3: Soap released (hand moved too far: %.2fcm)" % (dist_to_holder * 100))
			_release_soap()
			return
	
	# Try to grab if not currently held
	if not soap_held_by:
		if left_hand and is_instance_valid(left_hand):
			var dist = left_hand.global_position.distance_to(soap_body.global_position)
			if dist < scaled_grab:
				_try_grab_soap(left_hand)
				return
		
		if right_hand and is_instance_valid(right_hand):
			var dist = right_hand.global_position.distance_to(soap_body.global_position)
			if dist < scaled_grab:
				_try_grab_soap(right_hand)
				return


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


func _is_left_hand(node: Node) -> bool:
	var name_lower = node.name.to_lower()
	return "left" in name_lower


func _on_water_zone_area_entered(area: Area3D) -> void:
	if _is_hand_area(area):
		if _is_left_hand(area):
			left_hand_in_water = true
			print("Goal 3: LEFT HAND entered water zone")
		else:
			right_hand_in_water = true
			print("Goal 3: RIGHT HAND entered water zone")


func _on_water_zone_area_exited(area: Area3D) -> void:
	if _is_hand_area(area):
		if _is_left_hand(area):
			left_hand_in_water = false
			print("Goal 3: LEFT HAND exited water zone")
		else:
			right_hand_in_water = false
			print("Goal 3: RIGHT HAND exited water zone")


func _on_water_zone_body_entered(body: Node3D) -> void:
	# Also handle RigidBody3D/CharacterBody3D if hands are bodies
	var name_lower = body.name.to_lower()
	if "hand" in name_lower or "left" in name_lower or "right" in name_lower:
		if "left" in name_lower:
			left_hand_in_water = true
			print("Goal 3: LEFT HAND BODY entered water zone")
		else:
			right_hand_in_water = true
			print("Goal 3: RIGHT HAND BODY entered water zone")


func _on_water_zone_body_exited(body: Node3D) -> void:
	var name_lower = body.name.to_lower()
	if "hand" in name_lower or "left" in name_lower or "right" in name_lower:
		if "left" in name_lower:
			left_hand_in_water = false
		else:
			right_hand_in_water = false


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
	water_detection_area.collision_mask = 1  # Detect layer 1 (hands)
	water_detection_area.monitoring = true
	water_detection_area.monitorable = false

	var water_shape = CollisionShape3D.new()
	var water_box = BoxShape3D.new()
	water_box.size = Vector3(0.5, 0.3, 0.4)  # Larger detection zone for easier detection
	water_shape.shape = water_box
	water_detection_area.add_child(water_shape)

	# Connect signals for automatic detection
	water_detection_area.area_entered.connect(_on_water_zone_area_entered)
	water_detection_area.area_exited.connect(_on_water_zone_area_exited)
	water_detection_area.body_entered.connect(_on_water_zone_body_entered)
	water_detection_area.body_exited.connect(_on_water_zone_body_exited)

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
	water_particles.lifetime = 0.6  # Shorter lifetime so particles don't go through basin
	water_particles.one_shot = false
	water_particles.explosiveness = 0.0

	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 10.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3(0, -8, 0)
	mat.color = Color(0.3, 0.6, 0.95, 0.8)

	# Enable particle collision
	mat.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	mat.collision_bounce = 0.2
	mat.collision_friction = 0.5

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
	if not bar or not is_instance_valid(bar):
		return
	var fill = bar.get_node_or_null("Fill") as MeshInstance3D
	if fill and is_instance_valid(fill):
		var clamped = clamp(progress, 0.001, 1.0)  # Minimum visible progress
		fill.scale.x = clamped
		# Position so the left edge stays fixed and right edge extends
		fill.position.x = -0.24 + (0.24 * clamped)


func _setup_sink_collision() -> void:
	# Create StaticBody3D for soap/object collision
	var sink_collision = StaticBody3D.new()
	sink_collision.name = "SinkBasinCollision"
	sink_collision.collision_layer = 1
	sink_collision.collision_mask = 0

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.5, 0.05, 0.4)
	col_shape.shape = box
	sink_collision.add_child(col_shape)

	add_child(sink_collision)
	# Position at sink basin level
	sink_collision.position = Vector3(-0.1, 0.52, -0.22)

	# Create GPUParticlesCollisionBox3D for water particle collision
	var particle_collision = GPUParticlesCollisionBox3D.new()
	particle_collision.name = "SinkParticleCollision"
	particle_collision.size = Vector3(0.5, 0.1, 0.4)
	add_child(particle_collision)
	# Position slightly above basin to catch particles
	particle_collision.position = Vector3(-0.1, 0.54, -0.22)
	print("Goal 3: Sink particle collision added")


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

	# Enable soap physics - unfreeze and enable gravity
	if soap_body:
		soap_body.freeze = false
		soap_body.gravity_scale = 1.0
		print("Goal 3: Soap unfrozen at %s" % soap_body.global_position)

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

	# Continuously check for XR hands and reconnect signals if needed
	if not left_hand or not right_hand or not is_instance_valid(left_hand) or not is_instance_valid(right_hand):
		_get_xr_references()
		if left_hand and right_hand:
			_connect_fist_signals()

	# Apply manual gravity to soap (world gravity is 0)
	if soap_body and is_instance_valid(soap_body) and not soap_body.freeze:
		soap_body.apply_central_force(Vector3(0, -9.8 * soap_body.mass, 0))

	_update_soap_position()
	_check_proximity_grab()  # Auto-grab soap when hand gets close
	_check_hands_in_water()
	_check_soap_contact()
	_update_soap_particles()
	_update_progress(delta)
	_debug_scene_state(delta)


func _get_xr_references() -> void:
	if not xr_origin:
		xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		if not left_hand:
			left_hand = xr_origin.get_node_or_null("left")
		if not right_hand:
			right_hand = xr_origin.get_node_or_null("right")


func _check_hands_in_water() -> void:
	# Now handled by Area3D signals (_on_water_zone_area_entered/exited)
	# But we keep this function for potential fallback distance checks
	
	if not water_active:
		left_hand_in_water = false
		right_hand_in_water = false
		return
	
	# Signal-based detection is primary, but add fallback distance check
	if not water_detection_area or not is_instance_valid(water_detection_area):
		return
	
	var check_center = water_detection_area.global_position
	
	# Skip if position is still at origin (scene not fully loaded)
	if check_center.length_squared() < 0.01:
		return
	
	# Account for scene scale in distance check
	var scaled_radius = WATER_DETECTION_RADIUS * scale.x
	
	# Fallback: Check distance if signal-based detection didn't catch it
	if left_hand and is_instance_valid(left_hand) and not left_hand_in_water:
		var dist = left_hand.global_position.distance_to(check_center)
		if dist < scaled_radius:
			left_hand_in_water = true
			print("Goal 3: Left hand detected by fallback distance check")
	
	if right_hand and is_instance_valid(right_hand) and not right_hand_in_water:
		var dist = right_hand.global_position.distance_to(check_center)
		if dist < scaled_radius:
			right_hand_in_water = true
			print("Goal 3: Right hand detected by fallback distance check")


func _check_soap_contact() -> void:
	var was_touching = soap_touching_left or soap_touching_right
	soap_touching_left = false
	soap_touching_right = false

	if not soap_body or not is_instance_valid(soap_body):
		return

	var soap_pos = soap_body.global_position
	
	# Account for scene scale in detection radius
	var scaled_radius = SOAP_CONTACT_RADIUS * scale.x

	if left_hand and is_instance_valid(left_hand):
		var dist = left_hand.global_position.distance_to(soap_pos)
		if dist < scaled_radius:
			soap_touching_left = true

	if right_hand and is_instance_valid(right_hand):
		var dist = right_hand.global_position.distance_to(soap_pos)
		if dist < scaled_radius:
			soap_touching_right = true
	
	# Debug when soap contact starts
	var now_touching = soap_touching_left or soap_touching_right
	if now_touching and not was_touching:
		print("Goal 3: Soap contact started (left=%s, right=%s, scaled_radius=%.2f)" % [
			soap_touching_left, soap_touching_right, scaled_radius * 100
		])


func _update_soap_particles() -> void:
	if soap_particles_left:
		if left_hand and is_instance_valid(left_hand):
			soap_particles_left.global_position = left_hand.global_position
		soap_particles_left.emitting = soap_touching_left

	if soap_particles_right:
		if right_hand and is_instance_valid(right_hand):
			soap_particles_right.global_position = right_hand.global_position
		soap_particles_right.emitting = soap_touching_right


var _debug_timer: float = 0.0
func _debug_scene_state(delta: float) -> void:
	_debug_timer += delta
	if _debug_timer >= 5.0:  # Log every 5 seconds
		_debug_timer = 0.0
		
		print("=== Goal 3 DEBUG (every 5s) ===")
		print("  Scene scale: %s" % scale)
		print("  Water active: %s" % water_active)
		print("  Current state: %s" % GameState.keys()[current_state])
		
		if left_hand:
			print("  Left hand pos: %s" % left_hand.global_position)
		if right_hand:
			print("  Right hand pos: %s" % right_hand.global_position)
		
		if water_detection_area:
			print("  Water zone pos: %s" % water_detection_area.global_position)
			print("  Water zone scale: %s" % water_detection_area.global_scale)
			
		if soap_body:
			print("  Soap pos: %s (held=%s, frozen=%s)" % [
				soap_body.global_position,
				soap_held_by != null,
				soap_body.freeze
			])
		
		if left_hand and water_detection_area:
			var dist = left_hand.global_position.distance_to(water_detection_area.global_position)
			var threshold = WATER_DETECTION_RADIUS * scale.x
			print("  Left to water: %.2fcm (threshold=%.2fcm)" % [dist * 100, threshold * 100])
			
		if right_hand and water_detection_area:
			var dist = right_hand.global_position.distance_to(water_detection_area.global_position)
			var threshold = WATER_DETECTION_RADIUS * scale.x
			print("  Right to water: %.2fcm (threshold=%.2fcm)" % [dist * 100, threshold * 100])


func _update_progress(delta: float) -> void:
	if current_state != GameState.WASHING:
		return

	var hands_in_water = left_hand_in_water or right_hand_in_water
	var soap_active = soap_touching_left or soap_touching_right

	# Update water progress
	if hands_in_water and water_active:
		water_progress = min(water_progress + delta * WATER_FILL_RATE, 1.0)
	else:
		water_progress = max(water_progress - delta * WATER_DRAIN_RATE, 0.0)

	# Update soap progress
	if soap_active:
		soap_progress = min(soap_progress + delta * SOAP_FILL_RATE, 1.0)
	else:
		soap_progress = max(soap_progress - delta * SOAP_DRAIN_RATE, 0.0)

	# Update visual progress bars
	_update_progress_bar(water_progress_bar, water_progress)
	_update_progress_bar(soap_progress_bar, soap_progress)
	
	# Debug output every 2 seconds
	if int(Time.get_ticks_msec() / 2000.0) != int((Time.get_ticks_msec() - delta * 1000) / 2000.0):
		print("Goal 3: Water=%.1f%% (hands=%s), Soap=%.1f%% (soap=%s)" % [
			water_progress * 100, hands_in_water, soap_progress * 100, soap_active
		])

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
