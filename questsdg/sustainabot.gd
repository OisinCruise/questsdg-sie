class_name Sustainabot
extends Node3D

enum SustainabotState {
	IDLE, INSTRUCTING, COMMENDING, BERATING, SPRINTING, HIT,
	HIT_BELOW_WAIST,  # FallFlat animation
	HIT_GROIN,        # KickToTheGroin animation
	CELEBRATING       # Task complete celebration
}

signal state_changed(new_state: SustainabotState)
signal hit_by_object(object: Node3D)

# Animation mappings for random selection (names have "0" suffix from Mixamo)
const CORRECT_ANIMS: Array[String] = ["Cheering0", "Acknowledging0", "Thankful0", "Excited0"]
const HIT_TRASH_ANIMS: Array[String] = ["ShakeFist0", "HeadHit0", "PunchingBag0"]
const IDLE_ANIMS: Array[String] = ["Idle0", "DigAndPlantSeeds0", "Rummaging0", "LookOverShoulder0"]
const WALK_ANIMS: Array[String] = ["DrunkWalk0", "StrutWalking0"]
const TASK_COMPLETE_ANIMS: Array[String] = ["Shuffling0", "HipHopDancing0"]
const WRONG_PLACEMENT_ANIM: String = "DismissingGesture0"
const BELOW_WAIST_HIT_ANIM: String = "FallFlat0"
const GROIN_HIT_ANIM: String = "KickToTheGroin0"
const START_WALK_ANIM: String = "StartWalking0"

# Animation configuration
@export var gibberish_sounds: Array[AudioStream]
@export var use_tween_animations: bool = false
@export var walk_animation: String = "DrunkWalk0"
@export var tpose_animation: String = "Idle0"

# Height-based hit detection thresholds
@export var waist_height: float = 0.6
@export var chest_height: float = 1.2

# Speech bubble configuration
@export var speech_offset: Vector3 = Vector3(0, 2.2, 0)
@export var speech_font_size: int = 48

var current_state: SustainabotState = SustainabotState.IDLE
var animation_player: AnimationPlayer = null
var audio_player: AudioStreamPlayer3D = null
var speech_bubble: Label3D = null
var hit_area: Area3D = null

# Tween references
var idle_tween: Tween = null
var reaction_tween: Tween = null
var speech_tween: Tween = null

# Hit detection
var is_hit_cooldown: bool = false
var hit_cooldown_time: float = 2.0

# Store original position for animations
var base_position: Vector3 = Vector3.ZERO
var base_rotation: Vector3 = Vector3.ZERO

func _ready() -> void:
	base_position = position
	base_rotation = rotation
	_find_animation_player()
	_setup_audio_player()
	_setup_speech_bubble()
	_setup_hit_detection()
	_print_available_animations()

	# Start idle animation
	set_state("idle")

func _find_animation_player() -> void:
	if has_node("AnimationPlayer"):
		animation_player = $AnimationPlayer
	elif has_node("Model/AnimationPlayer"):
		animation_player = $Model/AnimationPlayer
	else:
		animation_player = _find_child_animation_player(self)

	# Connect animation_finished signal for auto-reset to idle
	if animation_player and not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)

func _find_child_animation_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found = _find_child_animation_player(child)
		if found:
			return found
	return null

func _setup_audio_player() -> void:
	if has_node("AudioStreamPlayer3D"):
		audio_player = $AudioStreamPlayer3D
	else:
		audio_player = AudioStreamPlayer3D.new()
		audio_player.name = "AudioStreamPlayer3D"
		audio_player.max_distance = 5.0
		audio_player.unit_size = 2.0
		add_child(audio_player)

func _setup_speech_bubble() -> void:
	speech_bubble = Label3D.new()
	speech_bubble.name = "SpeechBubble"
	speech_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	speech_bubble.font_size = speech_font_size
	speech_bubble.outline_size = 8
	speech_bubble.modulate = Color.WHITE
	speech_bubble.outline_modulate = Color.BLACK
	speech_bubble.position = speech_offset
	speech_bubble.visible = false
	speech_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speech_bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(speech_bubble)

func _setup_hit_detection() -> void:
	hit_area = Area3D.new()
	hit_area.name = "HitArea"
	hit_area.collision_layer = 0
	hit_area.collision_mask = 7  # Layers 1 (hands), 2 and 3 (waste items)

	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)

	hit_area.add_child(shape)
	add_child(hit_area)

	hit_area.body_entered.connect(_on_hit_by_body)
	hit_area.area_entered.connect(_on_hit_by_area)

func _print_available_animations() -> void:
	if animation_player:
		var anims = animation_player.get_animation_list()
		print("Sustainabot animations available: ", anims)
	else:
		push_warning("No AnimationPlayer found for Sustainabot")

func set_state(state_name: String) -> void:
	var previous_state = current_state

	match state_name.to_lower():
		"idle":
			current_state = SustainabotState.IDLE
		"instructing":
			current_state = SustainabotState.INSTRUCTING
		"commending":
			current_state = SustainabotState.COMMENDING
		"berating":
			current_state = SustainabotState.BERATING
		"sprinting":
			current_state = SustainabotState.SPRINTING
		"hit":
			current_state = SustainabotState.HIT
		"hit_below_waist":
			current_state = SustainabotState.HIT_BELOW_WAIST
		"hit_groin":
			current_state = SustainabotState.HIT_GROIN
		"celebrating":
			current_state = SustainabotState.CELEBRATING
		_:
			push_warning("Unknown Sustainabot state: " + state_name)
			return

	print("Sustainabot: State changed to ", state_name.to_upper())
	_play_state_animation()

	# Play gibberish for reactive states
	if current_state in [SustainabotState.INSTRUCTING, SustainabotState.COMMENDING,
			SustainabotState.BERATING, SustainabotState.HIT, SustainabotState.HIT_BELOW_WAIST,
			SustainabotState.HIT_GROIN, SustainabotState.CELEBRATING]:
		play_gibberish()

	emit_signal("state_changed", current_state)

func _play_state_animation() -> void:
	_stop_all_tweens()

	if use_tween_animations:
		match current_state:
			SustainabotState.IDLE:
				_play_base_animation()
				_play_idle_tween()
			SustainabotState.INSTRUCTING:
				_play_base_animation()
				_play_instructing_tween()
			SustainabotState.COMMENDING:
				_play_base_animation()
				_play_commending_tween()
			SustainabotState.BERATING:
				_play_base_animation()
				_play_berating_tween()
			SustainabotState.SPRINTING:
				_play_walk_animation()
			SustainabotState.HIT:
				_play_base_animation()
				_play_hit_reaction()
	else:
		# Fallback to GLB animations if available
		_play_glb_animation()

func _play_base_animation() -> void:
	if animation_player and animation_player.has_animation(tpose_animation):
		animation_player.play(tpose_animation)

func _play_walk_animation() -> void:
	if animation_player and animation_player.has_animation(walk_animation):
		animation_player.play(walk_animation)

func _pick_random_animation(anim_list: Array[String]) -> String:
	if anim_list.size() == 0:
		return "Idle0"
	return anim_list[randi() % anim_list.size()]

func _play_glb_animation() -> void:
	if not animation_player:
		return

	var anim_name: String
	match current_state:
		SustainabotState.IDLE:
			anim_name = _pick_random_animation(IDLE_ANIMS)
		SustainabotState.INSTRUCTING:
			anim_name = "Acknowledging0"  # Explaining gesture
		SustainabotState.COMMENDING:
			anim_name = _pick_random_animation(CORRECT_ANIMS)
		SustainabotState.BERATING:
			anim_name = WRONG_PLACEMENT_ANIM
		SustainabotState.SPRINTING:
			anim_name = _pick_random_animation(WALK_ANIMS)
		SustainabotState.HIT:
			anim_name = _pick_random_animation(HIT_TRASH_ANIMS)
		SustainabotState.HIT_BELOW_WAIST:
			anim_name = BELOW_WAIST_HIT_ANIM
		SustainabotState.HIT_GROIN:
			anim_name = GROIN_HIT_ANIM
		SustainabotState.CELEBRATING:
			anim_name = _pick_random_animation(TASK_COMPLETE_ANIMS)
		_:
			anim_name = "Idle0"

	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		print("Sustainabot: Playing animation '%s'" % anim_name)
	else:
		push_warning("Sustainabot: Animation '%s' not found" % anim_name)
		if animation_player.has_animation("Idle0"):
			animation_player.play("Idle0")

func _stop_all_tweens() -> void:
	if idle_tween and idle_tween.is_valid():
		idle_tween.kill()
	if reaction_tween and reaction_tween.is_valid():
		reaction_tween.kill()

	# Reset to base position/rotation
	position = base_position
	rotation = base_rotation

func _play_idle_tween() -> void:
	idle_tween = create_tween()
	idle_tween.set_loops()

	# More noticeable Y bob + slight rotation
	idle_tween.tween_property(self, "position:y", base_position.y + 0.15, 1.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	idle_tween.tween_property(self, "rotation:z", base_rotation.z + 0.05, 0.6)\
		.set_trans(Tween.TRANS_SINE)
	idle_tween.tween_property(self, "position:y", base_position.y, 1.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	idle_tween.tween_property(self, "rotation:z", base_rotation.z - 0.05, 0.6)\
		.set_trans(Tween.TRANS_SINE)
	idle_tween.tween_property(self, "rotation:z", base_rotation.z, 0.3)

func _play_instructing_tween() -> void:
	reaction_tween = create_tween()
	reaction_tween.set_loops(4)

	# Exaggerated head nod + arm-like rotation (lean forward/back)
	reaction_tween.tween_property(self, "rotation:x", base_rotation.x + 0.3, 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reaction_tween.tween_property(self, "position:z", base_position.z - 0.1, 0.15)
	reaction_tween.tween_property(self, "rotation:x", base_rotation.x - 0.1, 0.25)\
		.set_trans(Tween.TRANS_SINE)
	reaction_tween.tween_property(self, "position:z", base_position.z, 0.15)
	reaction_tween.tween_property(self, "rotation:x", base_rotation.x, 0.2)

func _play_commending_tween() -> void:
	reaction_tween = create_tween()

	# Excited jump + spin celebration
	reaction_tween.set_parallel(true)
	reaction_tween.tween_property(self, "position:y", base_position.y + 0.5, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reaction_tween.tween_property(self, "rotation:y", base_rotation.y + PI, 0.3)\
		.set_trans(Tween.TRANS_QUAD)
	reaction_tween.set_parallel(false)

	reaction_tween.tween_property(self, "position:y", base_position.y, 0.4)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	reaction_tween.tween_property(self, "rotation:y", base_rotation.y, 0.2)

	# Happy wiggle
	reaction_tween.tween_property(self, "rotation:z", base_rotation.z + 0.15, 0.1)
	reaction_tween.tween_property(self, "rotation:z", base_rotation.z - 0.15, 0.1)
	reaction_tween.tween_property(self, "rotation:z", base_rotation.z, 0.1)

	# Then start idle bob
	reaction_tween.tween_callback(_play_idle_tween)

func _play_berating_tween() -> void:
	reaction_tween = create_tween()

	# Angry stomp + aggressive shake
	reaction_tween.tween_property(self, "position:y", base_position.y + 0.1, 0.1)
	reaction_tween.tween_property(self, "position:y", base_position.y, 0.05)\
		.set_trans(Tween.TRANS_BOUNCE)

	# Frustrated head shake (more aggressive)
	for i in range(4):
		reaction_tween.tween_property(self, "rotation:y", base_rotation.y + 0.4, 0.08)\
			.set_trans(Tween.TRANS_ELASTIC)
		reaction_tween.tween_property(self, "rotation:y", base_rotation.y - 0.4, 0.08)\
			.set_trans(Tween.TRANS_ELASTIC)

	reaction_tween.tween_property(self, "rotation:y", base_rotation.y, 0.1)

	# Lean forward menacingly
	reaction_tween.tween_property(self, "rotation:x", base_rotation.x + 0.25, 0.2)
	reaction_tween.tween_interval(0.3)
	reaction_tween.tween_property(self, "rotation:x", base_rotation.x, 0.2)

	reaction_tween.tween_callback(_play_idle_tween)

func _play_hit_reaction() -> void:
	reaction_tween = create_tween()
	reaction_tween.set_parallel(true)

	# Knockback
	reaction_tween.tween_property(self, "position:z", base_position.z + 0.3, 0.15)\
		.set_trans(Tween.TRANS_QUAD)
	reaction_tween.tween_property(self, "position:y", base_position.y + 0.1, 0.15)\
		.set_trans(Tween.TRANS_QUAD)

	# Spin
	reaction_tween.tween_property(self, "rotation:y", base_rotation.y + TAU, 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	reaction_tween.set_parallel(false)

	# Return to position
	reaction_tween.tween_property(self, "position", base_position, 0.3)\
		.set_trans(Tween.TRANS_BOUNCE)

	# Resume idle
	reaction_tween.tween_callback(func(): set_state("idle"))

# Hit detection handlers
func _on_hit_by_body(body: Node3D) -> void:
	if body is XRGrabbable and not is_hit_cooldown:
		_react_to_hit(body, body.global_position, false)

func _on_hit_by_area(area: Area3D) -> void:
	var parent = area.get_parent()
	if parent is XRGrabbable and not is_hit_cooldown:
		_react_to_hit(parent, area.global_position, false)
	elif _is_hand_collision(area) and not is_hit_cooldown:
		# Hand collision
		_react_to_hit(area, area.global_position, true)

func _is_hand_collision(node: Node) -> bool:
	# Check if the node is related to hand tracking
	var node_name = node.name.to_lower()
	if "hand" in node_name:
		return true
	var parent = node.get_parent()
	if parent:
		var parent_name = parent.name.to_lower()
		if "hand" in parent_name:
			return true
	return false

func _react_to_hit(object: Node3D, hit_position: Vector3, is_hand: bool) -> void:
	is_hit_cooldown = true
	emit_signal("hit_by_object", object)

	# Calculate hit height relative to bot's base position
	var relative_hit_y = hit_position.y - global_position.y

	if relative_hit_y < waist_height:
		# Below waist - FallFlat
		set_state("hit_below_waist")
	elif relative_hit_y < chest_height and is_hand:
		# Hand between waist and chest - groin hit
		set_state("hit_groin")
	else:
		# Regular hit (above chest or non-hand below chest)
		set_state("hit")

	# Reset cooldown after delay
	get_tree().create_timer(hit_cooldown_time).timeout.connect(func(): is_hit_cooldown = false)

# Speech bubble methods
func show_speech(text: String, duration: float = 3.0) -> void:
	if speech_tween and speech_tween.is_valid():
		speech_tween.kill()

	speech_bubble.text = text
	speech_bubble.visible = true
	speech_bubble.scale = Vector3.ZERO

	speech_tween = create_tween()
	speech_tween.tween_property(speech_bubble, "scale", Vector3.ONE, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if duration > 0:
		speech_tween.tween_interval(duration)
		speech_tween.tween_callback(hide_speech)

func hide_speech() -> void:
	if speech_tween and speech_tween.is_valid():
		speech_tween.kill()

	speech_tween = create_tween()
	speech_tween.tween_property(speech_bubble, "scale", Vector3.ZERO, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	speech_tween.tween_callback(func(): speech_bubble.visible = false)

# Gibberish audio
func play_gibberish() -> void:
	if gibberish_sounds.size() == 0:
		print("Sustainabot: No gibberish sounds assigned!")
		return
	if not audio_player:
		print("Sustainabot: No audio player!")
		return

	var sound = gibberish_sounds[randi() % gibberish_sounds.size()]
	audio_player.stream = sound
	audio_player.pitch_scale = randf_range(0.7, 1.4)
	audio_player.volume_db = 0  # Ensure audible
	audio_player.play()
	print("Sustainabot: Playing gibberish (pitch: %.2f)" % audio_player.pitch_scale)

# Sprint to position (for intro sequence)
func sprint_to(target_pos: Vector3, duration: float = 1.5) -> void:
	set_state("sprinting")

	var sprint_tween = create_tween()
	sprint_tween.tween_property(self, "global_position", target_pos, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await sprint_tween.finished

	base_position = position
	set_state("idle")

func look_at_player(player_position: Vector3) -> void:
	var look_target = player_position
	look_target.y = global_position.y
	look_at(look_target, Vector3.UP)
	base_rotation = rotation

func get_state_name() -> String:
	match current_state:
		SustainabotState.IDLE:
			return "idle"
		SustainabotState.INSTRUCTING:
			return "instructing"
		SustainabotState.COMMENDING:
			return "commending"
		SustainabotState.BERATING:
			return "berating"
		SustainabotState.SPRINTING:
			return "sprinting"
		SustainabotState.HIT:
			return "hit"
		SustainabotState.HIT_BELOW_WAIST:
			return "hit_below_waist"
		SustainabotState.HIT_GROIN:
			return "hit_groin"
		SustainabotState.CELEBRATING:
			return "celebrating"
	return "unknown"

# Play StartWalking animation as transition before walking
func play_start_walk() -> void:
	if animation_player and animation_player.has_animation(START_WALK_ANIM):
		animation_player.play(START_WALK_ANIM)
		print("Sustainabot: Playing StartWalking transition")

# Reset to idle after certain animations complete
func _on_animation_finished(anim_name: StringName) -> void:
	# Reset to idle after hit animations complete
	var reset_anims = [BELOW_WAIST_HIT_ANIM, GROIN_HIT_ANIM]
	reset_anims.append_array(HIT_TRASH_ANIMS)

	if anim_name in reset_anims:
		print("Sustainabot: Animation '%s' finished, returning to idle" % anim_name)
		set_state("idle")
