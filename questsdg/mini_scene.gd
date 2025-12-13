class_name MiniScene
extends Node3D

signal task_started
signal task_completed(success: bool)
signal fade_complete
signal sustainabot_reaction(reaction_type: String)

@export var goal_number: int = 1
@export var scene_radius: float = 3.0

var sustainabot: Sustainabot = null
var feedback_manager: FeedbackManager = null
var is_active: bool = false
var fade_tween: Tween = null

func _ready() -> void:
	scale = Vector3.ZERO
	if has_node("Sustainabot"):
		sustainabot = $Sustainabot
	if has_node("FeedbackManager"):
		feedback_manager = $FeedbackManager
	setup_scene()

func setup_scene() -> void:
	pass

func start_scene() -> void:
	is_active = true
	_fade_in_environment()
	if sustainabot:
		sustainabot.set_state("instructing")
	emit_signal("task_started")

func end_scene() -> void:
	is_active = false
	if sustainabot:
		sustainabot.set_state("idle")
	_fade_out_environment()

func _fade_in_environment() -> void:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	fade_tween.tween_property(self, "scale", Vector3.ONE, 1.5)

func _fade_out_environment() -> void:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	fade_tween.tween_property(self, "scale", Vector3.ZERO, 1.0)
	fade_tween.finished.connect(_on_fade_out_complete)

func _on_fade_out_complete() -> void:
	emit_signal("fade_complete")

func report_action(correct: bool) -> void:
	if not sustainabot:
		return
	if correct:
		sustainabot.set_state("commending")
		if feedback_manager:
			feedback_manager.play_positive_feedback(sustainabot.global_position)
	else:
		sustainabot.set_state("berating")
		if feedback_manager:
			feedback_manager.play_negative_feedback(sustainabot.global_position)
	emit_signal("sustainabot_reaction", "commending" if correct else "berating")

func complete_task(success: bool) -> void:
	emit_signal("task_completed", success)
