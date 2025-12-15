class_name IntroSequence
extends Node3D

signal intro_completed
signal intro_started

@export var sustainabot: Sustainabot
@export var start_distance: float = 2.0  # meters behind final position
@export var sprint_duration: float = 1.5
@export var instruction_display_time: float = 4.0
@export var instruction_text: String = "Sort items into the bins!\nRecyclables -> Green bin\nWaste -> Gray bin"
@export var start_walk_duration: float = 0.3  # Duration for StartWalking transition

@export var whistle_sound: AudioStream

var audio_player: AudioStreamPlayer3D = null
var target_position: Vector3 = Vector3.ZERO
var is_playing: bool = false

func _ready() -> void:
	_setup_audio()

func _setup_audio() -> void:
	if has_node("WhistleAudio"):
		audio_player = $WhistleAudio
	else:
		audio_player = AudioStreamPlayer3D.new()
		audio_player.name = "WhistleAudio"
		audio_player.max_distance = 10.0
		audio_player.unit_size = 3.0
		add_child(audio_player)

func start_intro() -> void:
	if is_playing or not sustainabot:
		push_warning("IntroSequence: Cannot start - already playing or no Sustainabot")
		return

	is_playing = true
	emit_signal("intro_started")

	# Store final position and move bot to start behind user
	target_position = sustainabot.global_position
	# Bot spawns behind user (positive Z) and sprints toward bins (negative Z)
	var start_pos = target_position + Vector3(0, 0, start_distance)
	sustainabot.global_position = start_pos
	sustainabot.visible = true  # Ensure visible

	# Make bot face the bins/target position
	sustainabot.look_at_player(target_position)

	# Play whistle sound
	_play_whistle()

	await get_tree().create_timer(0.5).timeout

	# Sprint toward user
	await _sprint_to_user()

	# Show instruction popup
	_show_instructions()

	# Wait for instructions to display
	await get_tree().create_timer(instruction_display_time).timeout

	# Hide instructions
	sustainabot.hide_speech()

	await get_tree().create_timer(0.3).timeout

	is_playing = false
	emit_signal("intro_completed")

func _play_whistle() -> void:
	if whistle_sound and audio_player:
		audio_player.stream = whistle_sound
		audio_player.pitch_scale = randf_range(0.95, 1.05)
		audio_player.play()
	else:
		# If no whistle sound, use a short beep from existing sounds
		print("IntroSequence: No whistle sound assigned")

func _sprint_to_user() -> void:
	if not sustainabot:
		return

	# Play StartWalking animation as transition (brief start-up animation)
	sustainabot.play_start_walk()
	await get_tree().create_timer(start_walk_duration).timeout

	# Then switch to walking animation for the actual sprint
	sustainabot.set_state("sprinting")

	# Tween to target position
	var sprint_tween = create_tween()
	sprint_tween.tween_property(sustainabot, "global_position", target_position, sprint_duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await sprint_tween.finished

	# Update base position for animations
	sustainabot.base_position = sustainabot.position

func _show_instructions() -> void:
	if not sustainabot:
		return

	# Set to instructing state (plays head nod animation)
	sustainabot.set_state("instructing")

	# Show speech bubble with instructions
	sustainabot.show_speech(instruction_text, 0)  # 0 = don't auto-hide

	# Play gibberish while "talking"
	sustainabot.play_gibberish()

func skip_intro() -> void:
	# For testing - immediately complete intro
	if is_playing:
		return

	is_playing = false
	emit_signal("intro_completed")
