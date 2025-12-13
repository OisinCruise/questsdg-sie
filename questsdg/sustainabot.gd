class_name Sustainabot
extends Node3D

enum SustainabotState { IDLE, INSTRUCTING, COMMENDING, BERATING }

signal state_changed(new_state: SustainabotState)

@export var gibberish_sounds: Array[AudioStream]
@export var idle_animation: String = "idle"
@export var instructing_animation: String = "instructing"
@export var commending_animation: String = "commending"
@export var berating_animation: String = "berating"

var current_state: SustainabotState = SustainabotState.IDLE
var animation_player: AnimationPlayer = null
var audio_player: AudioStreamPlayer3D = null

func _ready() -> void:
	_find_animation_player()
	_setup_audio_player()
	_print_available_animations()

func _find_animation_player() -> void:
	if has_node("AnimationPlayer"):
		animation_player = $AnimationPlayer
	elif has_node("Model/AnimationPlayer"):
		animation_player = $Model/AnimationPlayer
	else:
		animation_player = _find_child_animation_player(self)

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
		audio_player.max_distance = 5.0
		audio_player.unit_size = 2.0
		add_child(audio_player)

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
		_:
			push_warning("Unknown Sustainabot state: " + state_name)
			return

	_play_state_animation()

	if current_state != SustainabotState.IDLE:
		play_gibberish()

	emit_signal("state_changed", current_state)

func _play_state_animation() -> void:
	if not animation_player:
		return

	var anim_name: String
	match current_state:
		SustainabotState.IDLE:
			anim_name = idle_animation
		SustainabotState.INSTRUCTING:
			anim_name = instructing_animation
		SustainabotState.COMMENDING:
			anim_name = commending_animation
		SustainabotState.BERATING:
			anim_name = berating_animation

	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)

func play_gibberish() -> void:
	if gibberish_sounds.size() == 0 or not audio_player:
		return

	var sound = gibberish_sounds[randi() % gibberish_sounds.size()]
	audio_player.stream = sound
	audio_player.pitch_scale = randf_range(0.8, 1.3)
	audio_player.play()

func look_at_player(player_position: Vector3) -> void:
	var look_target = player_position
	look_target.y = global_position.y
	look_at(look_target, Vector3.UP)

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
	return "unknown"
