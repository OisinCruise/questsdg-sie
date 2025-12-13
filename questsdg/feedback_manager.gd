class_name FeedbackManager
extends Node3D

@export var positive_particles: PackedScene = null
@export var negative_particles: PackedScene = null
@export var positive_sounds: Array[AudioStream] = []
@export var negative_sounds: Array[AudioStream] = []

var audio_player: AudioStreamPlayer3D = null

func _ready() -> void:
	if has_node("AudioStreamPlayer3D"):
		audio_player = $AudioStreamPlayer3D
	else:
		audio_player = AudioStreamPlayer3D.new()
		audio_player.max_distance = 5.0
		add_child(audio_player)

func play_positive_feedback(position: Vector3) -> void:
	_spawn_particles(positive_particles, position)
	_play_sound(positive_sounds)

func play_negative_feedback(position: Vector3) -> void:
	_spawn_particles(negative_particles, position)
	_play_sound(negative_sounds)

func _spawn_particles(particles_scene: PackedScene, pos: Vector3) -> void:
	if not particles_scene:
		return

	var particles = particles_scene.instantiate()
	add_child(particles)
	particles.global_position = pos

	if particles is GPUParticles3D:
		particles.emitting = true
		particles.finished.connect(func(): particles.queue_free())
	else:
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(particles):
			particles.queue_free()

func _play_sound(sounds: Array[AudioStream]) -> void:
	if sounds.size() == 0 or not audio_player:
		return

	var sound = sounds[randi() % sounds.size()]
	audio_player.stream = sound
	audio_player.pitch_scale = randf_range(0.9, 1.1)
	audio_player.play()

func play_custom_sound(sound: AudioStream, pitch_variance: float = 0.1) -> void:
	if not audio_player or not sound:
		return

	audio_player.stream = sound
	audio_player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	audio_player.play()
