# Goal 1 Water Pump Mini-Game Implementation Guide

## Overview
This guide provides step-by-step instructions for implementing a 30-second water pump mini-game where users fill buckets by operating a water pump. The game tracks the number of buckets filled and displays a score at the end.

**Goal 1 Theme**: No Poverty (Clean Water Access)

---

## Table of Contents
1. [Scene Structure Setup](#1-scene-structure-setup)
2. [Script Implementation](#2-script-implementation)
3. [3D Assets Setup](#3-3d-assets-setup)
4. [Water Pump Interaction](#4-water-pump-interaction)
5. [Bucket System](#5-bucket-system)
6. [Timer & UI System](#6-timer--ui-system)
7. [Game Logic Flow](#7-game-logic-flow)
8. [Testing & Tuning](#8-testing--tuning)

---

## 1. Scene Structure Setup

### 1.1 Open the Goal 1 Scene
1. In Godot, navigate to `mini_scenes/goal_1/goal_1_scene.tscn`
2. The scene should already have:
   - `Goal1Scene` (Node3D) - root node with `goal_1_scene.gd` script
   - `IntroSequence` (Node3D) - intro sequence controller
   - `Sustainabot` - character instance
   - `SpawnPoint` (Node3D) - reference point

### 1.2 Create Scene Hierarchy
Add the following nodes under `Goal1Scene`:

```
Goal1Scene (Node3D)
├── IntroSequence (already exists)
├── Sustainabot (already exists)
├── SpawnPoint (already exists)
├── WaterPump (Node3D) - NEW
│   ├── PumpModel (MeshInstance3D or GLB instance)
│   ├── PumpHandle (RigidBody3D) - NEW
│   │   ├── HandleMesh (MeshInstance3D)
│   │   ├── HandleCollision (CollisionShape3D)
│   │   └── HandDetectArea (Area3D) - NEW
│   │       └── DetectShape (CollisionShape3D)
│   └── WaterOutput (Node3D) - NEW (spawn point for water)
│       └── OutputMarker (MeshInstance3D - small sphere, invisible)
├── Buckets (Node3D) - NEW (container for all buckets)
│   ├── Bucket1 (Node3D) - NEW
│   │   ├── BucketMesh (MeshInstance3D or GLB)
│   │   ├── FillArea (Area3D) - NEW
│   │   │   └── FillShape (CollisionShape3D)
│   │   └── FillIndicator (MeshInstance3D) - NEW (water level visual)
│   ├── Bucket2 (Node3D) - NEW
│   │   └── [same structure as Bucket1]
│   └── Bucket3 (Node3D) - NEW
│       └── [same structure as Bucket1]
├── UI (CanvasLayer) - NEW
│   ├── TimerLabel (Label) - NEW
│   ├── ScoreLabel (Label) - NEW
│   └── EndScreen (Panel) - NEW
│       ├── FinalScoreLabel (Label)
│       ├── BucketsFilledLabel (Label)
│       └── MessageLabel (Label)
└── GameTimer (Timer) - NEW
```

### 1.3 Node Configuration Details

#### WaterPump Node
- **Position**: `(0, 0.5, -1.0)` - In front of user, slightly elevated
- **Rotation**: `(0, 180, 0)` - Face user
- **Purpose**: Main interaction point

#### PumpHandle (RigidBody3D)
- **Position**: `(0, 0.3, 0)` relative to WaterPump
- **Collision Layer**: `2` (same as trash bags in Goal 12)
- **Collision Mask**: `1` (environment)
- **Gravity Scale**: `0.0` (no gravity - constrained movement)
- **Freeze**: `true` initially
- **Mass**: `0.5`
- **Linear Damp**: `5.0` (smooth movement)
- **Angular Damp**: `10.0` (prevent spinning)

#### HandDetectArea (Area3D)
- **Collision Layer**: `0`
- **Collision Mask**: `1` (detect hands)
- **Shape**: SphereShape3D with radius `0.3`
- **Purpose**: Detect when hand is near pump handle

#### Buckets Node
- **Position**: `(0, 0, 0.5)` - Behind pump, in front of user
- **Layout**: Arrange 3-5 buckets in a row or arc
- **Spacing**: `0.8` units between buckets

#### FillArea (Area3D) per bucket
- **Collision Layer**: `0`
- **Collision Mask**: `4` (water particles - custom layer)
- **Shape**: BoxShape3D
  - **Size**: `(0.4, 0.3, 0.4)` - Slightly larger than bucket opening
  - **Position**: `(0, 0.2, 0)` - At bucket opening level

#### UI CanvasLayer
- **Mode**: `WORLD` (for 3D UI) OR `SCREEN` (for 2D overlay)
- **TimerLabel**: Top-center of screen
- **ScoreLabel**: Top-right of screen
- **EndScreen**: Full-screen overlay (initially hidden)

---

## 2. Script Implementation

### 2.1 Update `goal_1_scene.gd`

Replace the existing script with this implementation:

```gdscript
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
```

### 2.2 Create Pump Handle Script (Optional)

Create `pump_handle.gd` for more advanced handle behavior:

```gdscript
extends RigidBody3D

var original_position: Vector3
var min_y: float = -0.2  # Minimum Y offset for pump down
var max_y: float = 0.3   # Maximum Y offset for pump up
var is_being_pumped: bool = false

func _ready() -> void:
	original_position = position
	freeze = true  # Start frozen

func _physics_process(_delta: float) -> void:
	if freeze:
		return
	
	# Constrain handle movement to vertical axis
	var current_pos = position
	current_pos.x = original_position.x
	current_pos.z = original_position.z
	
	# Clamp Y position
	current_pos.y = clamp(current_pos.y, original_position.y + min_y, original_position.y + max_y)
	
	position = current_pos
	
	# Detect pump cycle (down then up)
	if current_pos.y <= original_position.y + min_y + 0.1:
		if not is_being_pumped:
			is_being_pumped = true
			# Emit signal for water generation
			get_parent().get_parent()._on_pump_cycle()  # Call parent scene method
	elif current_pos.y >= original_position.y + max_y - 0.1:
		is_being_pumped = false
```

---

## 3. 3D Assets Setup

### 3.1 Water Pump Model
**Option A: Use Existing Models**
- Search for "pump" or "well" models in your `Models/` folder
- Import a GLB/GLTF file as a MeshInstance3D
- Scale appropriately (recommended: 0.5-1.0 scale)

**Option B: Create Simple Pump**
1. Create a `CylinderMesh` for pump body
2. Create a `BoxMesh` for pump handle
3. Position handle above pump body
4. Apply materials (metal/wood textures)

**Recommended Pump Dimensions:**
- Body: Height `0.8m`, Radius `0.15m`
- Handle: Length `0.4m`, Width `0.05m`
- Handle Position: `(0, 0.3, 0)` relative to pump

### 3.2 Bucket Models
**Option A: Use Existing Models**
- Check `Models/` or `things/` folders for bucket/container models
- Import as MeshInstance3D instances

**Option B: Create Simple Buckets**
1. Create `CylinderMesh` for bucket body
2. Scale: `(0.3, 0.4, 0.3)` - wider than tall
3. Position 3-5 buckets in an arc or row
4. Apply materials (metal/plastic textures)

**Recommended Bucket Layout:**
- Spacing: `0.8m` between bucket centers
- Position: `(-0.8, 0, 0.5)`, `(0, 0, 0.5)`, `(0.8, 0, 0.5)`
- Height: `0.2m` above ground

### 3.3 Water Fill Indicator
For each bucket, create a `FillIndicator`:
1. Add `MeshInstance3D` child to bucket
2. Use `CylinderMesh` or `BoxMesh`
3. Scale: `(0.9, 0, 0.9)` initially (empty)
4. Material: Blue/cyan, semi-transparent
5. Position: `(0, -0.1, 0)` relative to bucket
6. Set `visible = false` initially

### 3.4 Water Output Point
1. Add `Node3D` child to `WaterPump` named `WaterOutput`
2. Add small `MeshInstance3D` with `SphereMesh` (radius `0.05m`)
3. Position: `(0, 0.2, 0.15)` - slightly forward from pump
4. Make invisible or use as visual reference
5. This is where "water" spawns from

---

## 4. Water Pump Interaction

### 4.1 Hand Detection Setup
The pump handle uses the same hand detection system as Goal 12:

1. **HandDetectArea** (Area3D)
   - Collision Mask: `1` (hands layer)
   - Shape: SphereShape3D, radius `0.3m`
   - When hand enters: Register handle as grabbable
   - When hand exits: Unregister handle

2. **Pump Handle** (RigidBody3D)
   - Collision Layer: `2`
   - Collision Mask: `1`
   - Freeze: `true` initially, `false` when game starts
   - Gravity Scale: `0.0` (constrained movement)

### 4.2 Pump Cycle Detection
Two approaches:

**Approach 1: Position-Based (Simpler)**
- Track handle Y position
- When Y < threshold (pushed down), count as cycle
- Reset when Y > threshold (pulled up)

**Approach 2: Release-Based (Current Implementation)**
- Count each handle release as a pump cycle
- Simpler but less realistic
- Good for MVP

### 4.3 Water Generation Logic
When pump cycle detected:
1. Check distance from `WaterOutput` to each unfilled bucket
2. If bucket within `2.0m` range, fill it
3. Play fill animation
4. Update score

**Improvement: Add Water Particles**
- Use `GPUParticles3D` for visual water stream
- Spawn from `WaterOutput` position
- Detect collision with bucket `FillArea`

---

## 5. Bucket System

### 5.1 Bucket Fill Detection
Each bucket has a `FillArea` (Area3D):
- **Collision Mask**: `4` (water particles layer - if using particles)
- **Shape**: BoxShape3D at bucket opening
- **Size**: Slightly larger than bucket opening
- **Position**: At bucket rim level

**Fill Logic:**
1. When water particle enters `FillArea`
2. OR when pump cycles and bucket is in range
3. Mark bucket as filled
4. Play fill animation
5. Increment `buckets_filled` counter

### 5.2 Fill Animation
For each bucket's `FillIndicator`:
1. Start: Scale Y = `0`, Position Y = `-0.1`
2. Animate: Scale Y → `1.0`, Position Y → `0.0`
3. Duration: `0.5` seconds
4. Use Tween with `TRANS_QUAD`, `EASE_OUT`

### 5.3 Bucket Reset
When scene restarts:
- Set `is_filled` meta to `false`
- Hide `FillIndicator`
- Reset indicator scale/position

---

## 6. Timer & UI System

### 6.1 Timer Setup
**GameTimer** (Timer node):
- **Wait Time**: `1.0` second (updates every second)
- **One Shot**: `false` (repeating)
- **Auto Start**: `false` (started manually)

**Timer Logic:**
- Decrement `time_remaining` each tick
- Update `TimerLabel` text
- When `time_remaining <= 0`, call `_end_game()`

### 6.2 UI Labels Setup

**TimerLabel** (Label):
- **Text**: `"Time: 00:30"`
- **Font Size**: `48` (adjust for visibility)
- **Position**: Top-center of screen
- **Format**: `"Time: %02d:%02d" % [minutes, seconds]`

**ScoreLabel** (Label):
- **Text**: `"Buckets: 0/3"`
- **Font Size**: `36`
- **Position**: Top-right of screen
- **Format**: `"Buckets: %d/%d" % [buckets_filled, total_buckets]`

### 6.3 End Screen Setup

**EndScreen** (Panel):
- **Size**: Full screen
- **Color**: Semi-transparent black background
- **Initially**: `visible = false`
- **Show**: When game ends

**FinalScoreLabel** (Label):
- **Text**: `"Final Score: X/3 Buckets"`
- **Font Size**: `64`
- **Position**: Center of panel

**BucketsFilledLabel** (Label):
- **Text**: `"Buckets Filled: X"`
- **Font Size**: `48`
- **Position**: Below final score

**MessageLabel** (Label):
- **Text**: Dynamic based on performance
- **Font Size**: `36`
- **Position**: Below buckets filled
- **Messages**:
  - All filled: `"Perfect! All buckets filled!"`
  - 2+ filled: `"Great job! Well done!"`
  - <2 filled: `"Good try! Keep practicing!"`

---

## 7. Game Logic Flow

### 7.1 Scene Start Flow
```
1. Scene loads → setup_scene() called
2. Find all nodes (pump, buckets, UI, etc.)
3. Setup signals and connections
4. Wait for fade-in (1.6s)
5. Connect hand signals
6. Start intro sequence
7. Intro completes → _start_game()
```

### 7.2 Gameplay Flow
```
1. Game starts → Timer starts, pump handle unfrozen
2. User grabs pump handle (pinch gesture)
3. User moves handle up/down
4. User releases handle → _on_pump_handle_released()
5. _check_pump_cycle() → _generate_water()
6. _generate_water() checks bucket distances
7. If bucket in range → _fill_bucket()
8. Bucket fill animation plays
9. Score increments, UI updates
10. Timer ticks every second
11. When time_remaining <= 0 → _end_game()
```

### 7.3 Game End Flow
```
1. Timer reaches 0 OR all buckets filled
2. _end_game() called
3. Freeze pump handle
4. Stop timer
5. Show end screen with results
6. Sustainabot gives final reaction
7. Wait 4 seconds
8. Track analytics
9. Call complete_task(success)
10. MiniSceneManager closes scene
```

---

## 8. Testing & Tuning

### 8.1 Initial Testing Checklist
- [ ] Scene loads without errors
- [ ] Intro sequence plays correctly
- [ ] Pump handle is grabbable
- [ ] Handle movement feels natural
- [ ] Pump cycles are detected
- [ ] Buckets fill when in range
- [ ] Timer counts down correctly
- [ ] UI updates properly
- [ ] End screen shows correct score
- [ ] Sustainabot reactions work
- [ ] Scene closes properly

### 8.2 Tuning Parameters

**Pump Handle:**
- `linear_damp`: `5.0` (smooth movement)
- `angular_damp`: `10.0` (prevent spinning)
- `mass`: `0.5` (not too heavy)
- Constraint range: Adjust `min_y`/`max_y` for handle travel

**Bucket Fill Range:**
- Default: `2.0m` from pump output
- Too easy? Increase to `1.5m`
- Too hard? Decrease to `2.5m`

**Game Duration:**
- Default: `30.0` seconds
- Too easy? Decrease to `25.0`
- Too hard? Increase to `35.0`

**Bucket Count:**
- Default: `3` buckets
- More challenging: `5` buckets
- Easier: `2` buckets

### 8.3 Common Issues & Solutions

**Issue: Handle not grabbable**
- Check `HandDetectArea` collision mask = `1`
- Verify hand signals are connected
- Check `pump_handle` collision layer = `2`

**Issue: Buckets not filling**
- Check bucket distances from `WaterOutput`
- Verify `FillArea` collision mask
- Check `is_filled` meta is being set correctly

**Issue: Timer not counting**
- Verify `GameTimer` is started in `_start_game()`
- Check `timeout` signal is connected
- Ensure `is_game_active` is `true`

**Issue: UI not updating**
- Check UI node paths in `_setup_ui()`
- Verify labels exist in scene tree
- Check `_update_ui()` is being called

---

## 9. Advanced Enhancements (Optional)

### 9.1 Water Particle System
Add visual water stream:
1. Create `GPUParticles3D` node
2. Position at `WaterOutput`
3. Configure emission: `10-20` particles/second
4. Set gravity: `-9.8` (downward)
5. Set collision: Detect bucket `FillArea`
6. Visual: Blue/cyan material

### 9.2 Sound Effects
Add audio feedback:
- Pump handle grab: `sounds/Sounds/Blip01.wav`
- Pump cycle: `sounds/Sounds/PowerUp10.wav`
- Bucket fill: `sounds/Sounds/Bing.wav`
- Timer warning (10s left): `sounds/Sounds/Beepecho03.wav`

### 9.3 Haptic Feedback
Add vibration on:
- Pump handle grab
- Pump cycle completion
- Bucket fill

### 9.4 Difficulty Levels
Adjust based on performance:
- Easy: 5 buckets, 40 seconds
- Medium: 3 buckets, 30 seconds (default)
- Hard: 5 buckets, 20 seconds

---

## 10. Integration with Main Scene

### 10.1 Verify MiniSceneManager Connection
The scene should automatically work with `MiniSceneManager`:
- Scene path: `mini_scenes/goal_1/goal_1_scene.tscn`
- Triggered by: Pinch gesture on Goal 1 animated box
- No additional setup needed if following structure

### 10.2 Testing in Main Scene
1. Run main scene (`cubes_scene_earlier.tscn`)
2. Navigate to Goal 1 box
3. Perform pinch gesture on animated box
4. Mini-scene should load
5. Test full gameplay flow

---

## Summary

This implementation provides:
- ✅ 30-second timed challenge
- ✅ Water pump interaction with hand tracking
- ✅ Bucket filling system with visual feedback
- ✅ Score tracking and end screen
- ✅ Sustainabot integration with reactions
- ✅ Intro sequence support
- ✅ Analytics tracking

**Next Steps:**
1. Create/import 3D models for pump and buckets
2. Set up scene hierarchy as described
3. Implement script in `goal_1_scene.gd`
4. Configure UI elements
5. Test and tune parameters
6. Add sound effects (optional)
7. Polish visual feedback

**Estimated Implementation Time:** 4-6 hours for basic version, 8-10 hours with polish and enhancements.

