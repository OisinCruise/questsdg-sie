extends MiniScene

# Game state
var buckets_filled: int = 0
var time_remaining: float = 30.0
var is_game_active: bool = false
var game_over: bool = false

# References
var buckets: Array = []  # Array of Bucket nodes
var pump_handle: Area3D = null
var water_spout: Node3D = null
var timer_label: Label3D = null
var score_label: Label3D = null
var instruction_label: Label3D = null
var whistle_player: AudioStreamPlayer3D = null

# Pump state
var is_pumping: bool = false
var water_particles: GPUParticles3D = null
var pump_cooldown: float = 0.0

# XR references
var xr_origin: XROrigin3D = null
var xr_camera: XRCamera3D = null

func setup_scene() -> void:
	goal_number = 1
	_get_references()
	_setup_water_particles()
	_connect_pump_handle()

func _get_references() -> void:
	# Find buckets
	if has_node("Buckets"):
		for child in $Buckets.get_children():
			if child.has_signal("filled"):  # Check if it's a bucket by signal
				buckets.append(child)
				child.filled.connect(_on_bucket_filled)

	# Find pump components
	if has_node("WaterPump/PumpHandle"):
		pump_handle = $WaterPump/PumpHandle
	if has_node("WaterPump/WaterSpout"):
		water_spout = $WaterPump/WaterSpout

	# Find UI
	if has_node("UI/TimerLabel"):
		timer_label = $UI/TimerLabel
	if has_node("UI/ScoreLabel"):
		score_label = $UI/ScoreLabel
	if has_node("UI/InstructionLabel"):
		instruction_label = $UI/InstructionLabel

	# Find audio
	if has_node("WhistlePlayer"):
		whistle_player = $WhistlePlayer

	# Find XR origin
	xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		xr_camera = xr_origin.get_node_or_null("XRCamera3D")

func _setup_water_particles() -> void:
	water_particles = GPUParticles3D.new()
	water_particles.emitting = false
	water_particles.amount = 30
	water_particles.lifetime = 0.8
	water_particles.one_shot = false

	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 10.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, -5, 0)
	mat.color = Color(0.2, 0.5, 0.9, 0.8)
	water_particles.process_material = mat

	var mesh = SphereMesh.new()
	mesh.radius = 0.015
	mesh.height = 0.03
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.2, 0.5, 0.9, 0.7)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat
	water_particles.draw_pass_1 = mesh

	if water_spout:
		water_spout.add_child(water_particles)
	else:
		add_child(water_particles)
		water_particles.position = Vector3(0, 0.35, -1.05)

func _connect_pump_handle() -> void:
	if pump_handle:
		pump_handle.area_entered.connect(_on_pump_area_entered)
		pump_handle.area_exited.connect(_on_pump_area_exited)

func _on_pump_area_entered(area: Area3D) -> void:
	if "hand" in area.name.to_lower() or "hand" in area.get_parent().name.to_lower():
		_activate_pump()

func _on_pump_area_exited(area: Area3D) -> void:
	if "hand" in area.name.to_lower() or "hand" in area.get_parent().name.to_lower():
		_deactivate_pump()

func _activate_pump() -> void:
	if not is_game_active or pump_cooldown > 0:
		return
	is_pumping = true
	if water_particles:
		water_particles.emitting = true

func _deactivate_pump() -> void:
	is_pumping = false
	if water_particles:
		water_particles.emitting = false

func start_scene() -> void:
	super.start_scene()

	# Set Sustainabot skin color to Goal 1 red (No Poverty)
	if sustainabot:
		sustainabot.set_skin_color(Color("#E5243B"))

	# Reset state
	buckets_filled = 0
	time_remaining = 30.0
	is_game_active = false
	game_over = false

	# Reset buckets
	for bucket in buckets:
		bucket.reset()
		bucket.freeze = true

	_update_ui()

	# Wait for fade in
	await get_tree().create_timer(1.5).timeout

	# Play whistle and start intro
	if whistle_player:
		whistle_player.play()

	# Sustainabot walks to player
	if sustainabot and xr_camera:
		var target_pos = xr_camera.global_position + Vector3(1.5, 0, -1)
		target_pos.y = 0
		await sustainabot.sprint_to(target_pos, 2.0)
		sustainabot.look_at_player(xr_camera.global_position)

	# Show instructions
	if sustainabot:
		sustainabot.set_state("instructing")
		sustainabot.show_speech("Fill the buckets\nwith water!", 3.0)

	if instruction_label:
		instruction_label.text = "Grab buckets and place under spout\nTouch pump handle to release water"

	await get_tree().create_timer(3.0).timeout

	# Start game
	_start_game()

func _start_game() -> void:
	is_game_active = true

	# Unfreeze buckets
	for bucket in buckets:
		bucket.freeze = false

	if instruction_label:
		instruction_label.text = ""

	if sustainabot:
		sustainabot.set_state("idle")
		sustainabot.show_speech("Go!", 1.5)

func _process(delta: float) -> void:
	if not is_game_active or game_over:
		return

	# Update timer
	time_remaining -= delta
	if time_remaining <= 0:
		time_remaining = 0
		_end_game(false)
		return

	# Update pump cooldown
	if pump_cooldown > 0:
		pump_cooldown -= delta

	# Check bucket filling
	if is_pumping and water_spout:
		_check_bucket_filling(delta)

	_update_ui()

	# Make sustainabot follow player slightly
	if sustainabot and xr_camera and is_game_active:
		sustainabot.look_at_player(xr_camera.global_position)

	# Apply manual gravity to unfrozen buckets (since world gravity is 0)
	for bucket in buckets:
		if is_instance_valid(bucket) and not bucket.freeze:
			bucket.apply_central_force(Vector3(0, -9.8 * bucket.mass, 0))
			# Keep buckets upright for easier placement
			_apply_upright_correction(bucket, delta)

func _apply_upright_correction(body: RigidBody3D, delta_time: float) -> void:
	var current_up = body.global_transform.basis.y
	var target_up = Vector3.UP
	var dot = current_up.dot(target_up)

	if dot < 0.99:
		var axis = current_up.cross(target_up)
		if axis.length_squared() > 0.0001:
			axis = axis.normalized()
			var correction_strength = 15.0 * (1.0 - dot)
			body.apply_torque(axis * correction_strength)
			body.angular_velocity = body.angular_velocity.lerp(Vector3.ZERO, delta_time * 5.0)

func _check_bucket_filling(delta: float) -> void:
	var spout_pos = water_spout.global_position

	for bucket in buckets:
		if bucket.is_filled:
			continue

		var bucket_pos = bucket.global_position
		var horizontal_dist = Vector2(spout_pos.x - bucket_pos.x, spout_pos.z - bucket_pos.z).length()

		# Bucket must be under spout and below it
		if horizontal_dist < 0.25 and bucket_pos.y < spout_pos.y:
			bucket.add_water(delta)

func _on_bucket_filled() -> void:
	buckets_filled += 1
	_update_ui()

	if sustainabot:
		sustainabot.set_state("commending")
		sustainabot.show_speech("Great job!", 2.0)

	# Check win condition (all 4 buckets filled)
	if buckets_filled >= 4:
		_end_game(true)

func _update_ui() -> void:
	if timer_label:
		var mins = int(time_remaining) / 60
		var secs = int(time_remaining) % 60
		timer_label.text = "Time: %d:%02d" % [mins, secs]

		# Color warning
		if time_remaining <= 10:
			timer_label.modulate = Color.RED
		elif time_remaining <= 20:
			timer_label.modulate = Color.YELLOW
		else:
			timer_label.modulate = Color.WHITE

	if score_label:
		score_label.text = "Buckets: %d/4" % buckets_filled

func _end_game(won: bool) -> void:
	if game_over:
		return

	game_over = true
	is_game_active = false
	_deactivate_pump()

	# Freeze buckets
	for bucket in buckets:
		bucket.freeze = true

	# Sustainabot reaction
	if sustainabot:
		if won or buckets_filled >= 3:
			sustainabot.set_state("celebrating")
			sustainabot.show_speech("Well done!\n%d buckets filled!" % buckets_filled, 4.0)
		else:
			sustainabot.set_state("berating")
			sustainabot.show_speech("Only %d buckets...\nTry harder!" % buckets_filled, 4.0)

	# Show final message
	if instruction_label:
		if won:
			instruction_label.text = "Perfect! All buckets filled!"
			instruction_label.modulate = Color.GREEN
		elif buckets_filled >= 3:
			instruction_label.text = "Great effort!"
			instruction_label.modulate = Color.YELLOW
		else:
			instruction_label.text = "Keep practicing!"
			instruction_label.modulate = Color.RED

	# Track analytics
	Talo.events.track("Goal 1 completed", {
		"buckets_filled": str(buckets_filled),
		"time_remaining": str(int(time_remaining)),
		"won": str(won)
	})

	await get_tree().create_timer(4.0).timeout

	# Complete task (success if 3+ buckets)
	complete_task(buckets_filled >= 3)

func end_scene() -> void:
	is_game_active = false
	game_over = false
	_deactivate_pump()
	super.end_scene()
