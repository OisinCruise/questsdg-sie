extends MiniScene

# Game state
var buckets_filled: int = 0
var total_buckets: int = 3
var game_time_limit: float = 30.0
var time_remaining: float = 30.0
var is_game_active: bool = false
var is_game_complete: bool = false

# References
var intro_sequence: IntroSequence = null
var water_pump: Node3D = null
var pump_handle: RigidBody3D = null
var hand_detect_area: Area3D = null
var buckets: Array[Node3D] = []
var bucket_fill_areas: Array[Area3D] = []
var game_timer: Timer = null

# UI References
var timer_label: Label = null
var score_label: Label = null
var end_screen: Panel = null
var final_score_label: Label = null
var buckets_filled_label: Label = null
var message_label: Label = null

# Water pump state
var is_pump_active: bool = false
var pump_handle_held: bool = false
var pump_cycles: int = 0
var water_particles_active: bool = false

# Water particle system (optional - for visual feedback)
var water_particle_system: GPUParticles3D = null

func setup_scene() -> void:
	goal_number = 1
	
	# Find intro sequence
	if has_node("IntroSequence"):
		intro_sequence = $IntroSequence
		intro_sequence.sustainabot = sustainabot
		intro_sequence.instruction_text = "Fill as many buckets as you can!\nUse the pump handle to pump water.\nYou have 30 seconds!"
	
	# Find water pump components
	if has_node("WaterPump"):
		water_pump = $WaterPump
		if water_pump.has_node("PumpHandle"):
			pump_handle = water_pump.get_node("PumpHandle")
			if pump_handle.has_node("HandDetectArea"):
				hand_detect_area = pump_handle.get_node("HandDetectArea")
				_setup_hand_detection()
	
	# Find buckets
	_find_buckets()
	
	# Setup game timer
	_setup_timer()
	
	# Setup UI
	_setup_ui()
	
	# Connect Sustainabot hit detection
	_connect_sustainabot_hit()

func _setup_hand_detection() -> void:
	if not hand_detect_area:
		return
	
	# Connect area signals for hand detection
	if not hand_detect_area.area_entered.is_connected(_on_hand_area_entered):
		hand_detect_area.area_entered.connect(_on_hand_area_entered)
	if not hand_detect_area.area_exited.is_connected(_on_hand_area_exited):
		hand_detect_area.area_exited.connect(_on_hand_area_exited)

func _on_hand_area_entered(area: Area3D) -> void:
	# Register pump handle as grabbable
	var parent = area.get_parent()
	if parent and parent.has_method("register_nearby_grabbable"):
		parent.register_nearby_grabbable(pump_handle)

func _on_hand_area_exited(area: Area3D) -> void:
	# Unregister when hand leaves
	var parent = area.get_parent()
	if parent and parent.has_method("unregister_nearby_grabbable"):
		parent.unregister_nearby_grabbable(pump_handle)

func _find_buckets() -> void:
	buckets.clear()
	bucket_fill_areas.clear()
	
	if not has_node("Buckets"):
		push_warning("Goal 1: No Buckets node found")
		return
	
	var buckets_node = $Buckets
	for child in buckets_node.get_children():
		if child is Node3D:
			buckets.append(child)
			# Find FillArea in each bucket
			if child.has_node("FillArea"):
				var fill_area = child.get_node("FillArea") as Area3D
				bucket_fill_areas.append(fill_area)
				_setup_bucket_area(fill_area, child)

func _setup_bucket_area(fill_area: Area3D, bucket_node: Node3D) -> void:
	# Connect signals for water detection
	if not fill_area.body_entered.is_connected(_on_water_entered_bucket):
		fill_area.body_entered.connect(func(body): _on_water_entered_bucket(fill_area, body))
	
	# Store reference to bucket node
	fill_area.set_meta("bucket_node", bucket_node)
	fill_area.set_meta("is_filled", false)

func _setup_timer() -> void:
	if has_node("GameTimer"):
		game_timer = $GameTimer
	else:
		game_timer = Timer.new()
		game_timer.name = "GameTimer"
		game_timer.wait_time = 1.0  # Update every second
		game_timer.one_shot = false
		add_child(game_timer)
	
	game_timer.timeout.connect(_on_timer_tick)

func _setup_ui() -> void:
	if not has_node("UI"):
		push_warning("Goal 1: No UI node found")
		return
	
	var ui = $UI
	if ui.has_node("TimerLabel"):
		timer_label = ui.get_node("TimerLabel")
	if ui.has_node("ScoreLabel"):
		score_label = ui.get_node("ScoreLabel")
	if ui.has_node("EndScreen"):
		end_screen = ui.get_node("EndScreen")
		if end_screen.has_node("FinalScoreLabel"):
			final_score_label = end_screen.get_node("FinalScoreLabel")
		if end_screen.has_node("BucketsFilledLabel"):
			buckets_filled_label = end_screen.get_node("BucketsFilledLabel")
		if end_screen.has_node("MessageLabel"):
			message_label = end_screen.get_node("MessageLabel")
	
	# Hide end screen initially
	if end_screen:
		end_screen.visible = false
	
	_update_ui()

func _connect_sustainabot_hit() -> void:
	if sustainabot:
		sustainabot.hit_by_object.connect(_on_sustainabot_hit)

func start_scene() -> void:
	super.start_scene()
	
	# Reset game state
	buckets_filled = 0
	time_remaining = game_time_limit
	is_game_active = false
	is_game_complete = false
	pump_cycles = 0
	
	# Reset all buckets
	for fill_area in bucket_fill_areas:
		fill_area.set_meta("is_filled", false)
		_reset_bucket_visual(fill_area.get_meta("bucket_node"))
	
	# Wait for scene fade-in
	await get_tree().create_timer(1.6).timeout
	
	# Connect hand signals for pump handle
	_connect_hand_signals()
	
	# Run intro sequence
	if intro_sequence and sustainabot:
		intro_sequence.intro_completed.connect(_on_intro_completed, CONNECT_ONE_SHOT)
		intro_sequence.start_intro()
	else:
		_start_game()

func _connect_hand_signals() -> void:
	# Find hands and connect to their release signals
	var hands = get_tree().get_nodes_in_group("xr_hand")
	for hand in hands:
		if hand.has_signal("object_released"):
			if not hand.object_released.is_connected(_on_pump_handle_released):
				hand.object_released.connect(_on_pump_handle_released)
		if hand.has_signal("pinch_started"):
			if not hand.pinch_started.is_connected(_on_pump_handle_grabbed):
				hand.pinch_started.connect(_on_pump_handle_grabbed)
	
	# Also try to find hands by path
	var xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		for child_name in ["left", "right"]:
			var hand = xr_origin.get_node_or_null(child_name)
			if hand and hand.has_signal("object_released"):
				if not hand.object_released.is_connected(_on_pump_handle_released):
					hand.object_released.connect(_on_pump_handle_released)
			if hand and hand.has_signal("pinch_started"):
				if not hand.pinch_started.is_connected(_on_pump_handle_grabbed):
					hand.pinch_started.connect(_on_pump_handle_grabbed)

func _on_intro_completed() -> void:
	if is_active:
		_start_game()

func _start_game() -> void:
	is_game_active = true
	game_timer.start()
	
	# Enable pump handle
	if pump_handle:
		pump_handle.freeze = false
	
	# Update UI
	_update_ui()
	
	# Sustainabot encouragement
	if sustainabot:
		sustainabot.set_state("instructing")
		sustainabot.show_speech("Go! Fill those buckets!", 2.0)

func _on_timer_tick() -> void:
	if not is_game_active or is_game_complete:
		return
	
	time_remaining -= 1.0
	
	if time_remaining <= 0:
		time_remaining = 0
		_end_game()
	
	_update_ui()

func _update_ui() -> void:
	if timer_label:
		var minutes = int(time_remaining) / 60
		var seconds = int(time_remaining) % 60
		timer_label.text = "Time: %02d:%02d" % [minutes, seconds]
	
	if score_label:
		score_label.text = "Buckets: %d/%d" % [buckets_filled, total_buckets]

func _on_pump_handle_grabbed() -> void:
	# Check if handle is being grabbed
	if not pump_handle:
		return
	
	# This will be called when pinch starts, but we need to check if handle is held
	# The actual grab detection happens in hand.gd
	pump_handle_held = true

func _on_pump_handle_released(object: RigidBody3D) -> void:
	if object != pump_handle:
		return
	
	pump_handle_held = false
	
	# Check if handle was moved enough to count as a pump cycle
	_check_pump_cycle()

func _check_pump_cycle() -> void:
	if not is_game_active:
		return
	
	# Simple check: if handle moved down and back up, count as cycle
	# For now, we'll use a simpler approach: count releases as cycles
	pump_cycles += 1
	
	# Generate water
	_generate_water()

func _generate_water() -> void:
	if not is_game_active:
		return
	
	# Create water particles or simple detection
	# For simplicity, we'll use a simple area-based system
	# Water "flows" from pump output to buckets
	
	# Check if any bucket is in range and not filled
	for fill_area in bucket_fill_areas:
		if fill_area.get_meta("is_filled", false):
			continue
		
		# Simple distance check - if bucket is close enough, fill it
		var bucket_node = fill_area.get_meta("bucket_node") as Node3D
		if not bucket_node:
			continue
		
		var pump_output_pos = Vector3.ZERO
		if water_pump and water_pump.has_node("WaterOutput"):
			pump_output_pos = water_pump.get_node("WaterOutput").global_position
		else:
			pump_output_pos = water_pump.global_position if water_pump else Vector3.ZERO
		
		var bucket_pos = bucket_node.global_position
		var distance = pump_output_pos.distance_to(bucket_pos)
		
		# If bucket is within 2 meters and in front of pump, fill it
		if distance < 2.0:
			_fill_bucket(fill_area, bucket_node)

func _on_water_entered_bucket(fill_area: Area3D, body: Node3D) -> void:
	# This is called when a water particle/body enters the bucket area
	# For now, we'll use the distance-based system in _generate_water()
	pass

func _fill_bucket(fill_area: Area3D, bucket_node: Node3D) -> void:
	if fill_area.get_meta("is_filled", false):
		return
	
	# Mark as filled
	fill_area.set_meta("is_filled", true)
	buckets_filled += 1
	
	# Visual feedback
	_show_bucket_filled(bucket_node)
	
	# Audio feedback (optional)
	# play_sound("bucket_fill.wav")
	
	# Sustainabot reaction
	if sustainabot:
		sustainabot.set_state("commending")
		sustainabot.show_speech("Great! Bucket %d filled!" % buckets_filled, 1.5)
		report_action(true)
	
	# Update UI
	_update_ui()
	
	# Check if all buckets filled
	if buckets_filled >= total_buckets:
		_end_game()

func _show_bucket_filled(bucket_node: Node3D) -> void:
	# Show visual indicator that bucket is filled
	if bucket_node.has_node("FillIndicator"):
		var indicator = bucket_node.get_node("FillIndicator") as MeshInstance3D
		indicator.visible = true
		# Animate water level rising
		var tween = create_tween()
		indicator.scale = Vector3(1, 0, 1)
		indicator.position.y = -0.1
		tween.tween_property(indicator, "scale", Vector3(1, 1, 1), 0.5)
		tween.parallel().tween_property(indicator, "position:y", 0.0, 0.5)

func _reset_bucket_visual(bucket_node: Node3D) -> void:
	if bucket_node.has_node("FillIndicator"):
		var indicator = bucket_node.get_node("FillIndicator") as MeshInstance3D
		indicator.visible = false
		indicator.scale = Vector3(1, 0, 1)
		indicator.position.y = -0.1

func _end_game() -> void:
	if is_game_complete:
		return
	
	is_game_complete = true
	is_game_active = false
	game_timer.stop()
	
	# Freeze pump handle
	if pump_handle:
		pump_handle.freeze = true
	
	# Show end screen
	_show_end_screen()
	
	# Sustainabot final reaction
	if sustainabot:
		var success = buckets_filled >= 2  # At least 2/3 buckets
		if success:
			sustainabot.set_state("celebrating")
			sustainabot.show_speech("Excellent work!\nYou filled %d buckets!" % buckets_filled, 3.0)
		else:
			sustainabot.set_state("berating")
			sustainabot.show_speech("Only %d buckets?\nTry harder next time!" % buckets_filled, 3.0)
	
	# Wait before completing task
	await get_tree().create_timer(4.0).timeout
	
	# Track analytics
	Talo.events.track("Goal 1 buckets filled", {
		"buckets": str(buckets_filled),
		"total": str(total_buckets),
		"time_remaining": str(time_remaining)
	})
	
	# Complete task (success if 2+ buckets)
	complete_task(buckets_filled >= 2)

func _show_end_screen() -> void:
	if not end_screen:
		return
	
	end_screen.visible = true
	
	if final_score_label:
		final_score_label.text = "Final Score: %d/%d Buckets" % [buckets_filled, total_buckets]
	
	if buckets_filled_label:
		buckets_filled_label.text = "Buckets Filled: %d" % buckets_filled
	
	if message_label:
		if buckets_filled >= total_buckets:
			message_label.text = "Perfect! All buckets filled!"
		elif buckets_filled >= 2:
			message_label.text = "Great job! Well done!"
		else:
			message_label.text = "Good try! Keep practicing!"

func _on_sustainabot_hit(object: Node3D) -> void:
	if not sustainabot:
		return
	
	var messages: Array[String] = [
		"Hey! Watch the pump!",
		"Don't throw things at me!",
		"The buckets are over there!",
		"Focus on the task!"
	]
	
	var msg = messages[randi() % messages.size()]
	sustainabot.show_speech(msg, 2.0)
	
	Talo.events.track("Goal 1 object thrown at bot", {"object": object.name})

func _physics_process(_delta: float) -> void:
	# Sync pump handle visual if needed
	# Track handle position for pump cycle detection
	if pump_handle and pump_handle_held:
		# Check handle position relative to pump
		var handle_pos = pump_handle.global_position
		var pump_pos = water_pump.global_position if water_pump else Vector3.ZERO
		var relative_y = handle_pos.y - pump_pos.y
		
		# If handle moved down significantly, it's a pump cycle
		# This is a simplified check - you may want to improve this

func end_scene() -> void:
	is_game_active = false
	is_game_complete = false
	if game_timer:
		game_timer.stop()
	if end_screen:
		end_screen.visible = false
	super.end_scene()
