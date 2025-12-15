class_name TargetZone
extends Area3D

signal object_placed(object: Node3D, correct: bool)

@export var accepted_tags: Array[String] = []
@export var feedback_correct: AudioStream = null
@export var feedback_incorrect: AudioStream = null
@export var consume_object: bool = true

var audio_player: AudioStreamPlayer3D = null

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

	if has_node("AudioStreamPlayer3D"):
		audio_player = $AudioStreamPlayer3D
	else:
		audio_player = AudioStreamPlayer3D.new()
		audio_player.max_distance = 3.0
		add_child(audio_player)

func _on_area_entered(area: Area3D) -> void:
	var grabbable = _find_grabbable(area)
	if grabbable:
		_process_grabbable(grabbable)

func _on_body_entered(body: Node3D) -> void:
	# Handle XRGrabbable
	if body is XRGrabbable:
		_process_grabbable(body)
	# Handle any RigidBody3D in the "grabbable" group (scene_grabbable)
	elif body is RigidBody3D and body.is_in_group("grabbable"):
		_process_grabbable(body)

func _find_grabbable(node: Node) -> Node3D:
	if node is XRGrabbable:
		return node
	if node.get_parent() is XRGrabbable:
		return node.get_parent()
	# Check for scene_grabbable (RigidBody3D in grabbable group)
	if node is RigidBody3D and node.is_in_group("grabbable"):
		return node
	if node.get_parent() is RigidBody3D and node.get_parent().is_in_group("grabbable"):
		return node.get_parent()
	return null

func _process_grabbable(grabbable: Node3D) -> void:
	# Check if grabbed (works for both XRGrabbable and scene_grabbable)
	if grabbable.get("is_grabbed"):
		return

	var is_correct = check_if_correct(grabbable)
	_play_feedback(is_correct)

	# Call on_placed_in_target if method exists
	if grabbable.has_method("on_placed_in_target"):
		grabbable.on_placed_in_target(self)

	emit_signal("object_placed", grabbable, is_correct)

	if consume_object:
		var tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		tween.tween_property(grabbable, "scale", Vector3.ZERO, 0.3)
		tween.finished.connect(func(): grabbable.queue_free())

func check_if_correct(grabbable: Node3D) -> bool:
	for tag in accepted_tags:
		if grabbable.is_in_group(tag):
			return true
	return false

func _play_feedback(correct: bool) -> void:
	if not audio_player:
		return

	var stream = feedback_correct if correct else feedback_incorrect
	if stream:
		audio_player.stream = stream
		audio_player.pitch_scale = randf_range(0.9, 1.1)
		audio_player.play()
