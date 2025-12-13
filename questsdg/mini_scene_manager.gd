class_name MiniSceneManager
extends Node3D

signal scene_opened(goal_number: int)
signal scene_closed(goal_number: int)
signal task_completed(goal_number: int, success: bool)

var current_mini_scene: MiniScene = null
var xr_origin: XROrigin3D = null
var is_transitioning: bool = false

func _ready() -> void:
	xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if not xr_origin:
		var origins = get_tree().get_nodes_in_group("xr_origin")
		if origins.size() > 0:
			xr_origin = origins[0]

func open_mini_scene(goal_number: int) -> void:
	if current_mini_scene or is_transitioning:
		return

	is_transitioning = true

	var scene_path = "res://mini_scenes/goal_%d/goal_%d_scene.tscn" % [goal_number, goal_number]

	if not ResourceLoader.exists(scene_path):
		push_warning("Mini-scene not found: " + scene_path)
		is_transitioning = false
		return

	var scene_res = load(scene_path)
	if scene_res:
		current_mini_scene = scene_res.instantiate()
		add_child(current_mini_scene)

		if xr_origin:
			current_mini_scene.global_position = xr_origin.global_position

		current_mini_scene.task_completed.connect(_on_task_completed)
		current_mini_scene.start_scene()

		emit_signal("scene_opened", goal_number)

		Talo.events.track("Goal %d mini-scene started" % goal_number)

	is_transitioning = false

func close_current_scene(success: bool = true) -> void:
	if not current_mini_scene or is_transitioning:
		return

	is_transitioning = true

	var goal_num = current_mini_scene.goal_number

	current_mini_scene.end_scene()

	await current_mini_scene.fade_complete

	current_mini_scene.queue_free()
	current_mini_scene = null

	emit_signal("scene_closed", goal_num)
	emit_signal("task_completed", goal_num, success)

	Talo.events.track("Goal %d task completed" % goal_num, {"success": str(success)})
	Talo.events.flush()

	is_transitioning = false

func _on_task_completed(success: bool) -> void:
	close_current_scene(success)

func is_in_mini_scene() -> bool:
	return current_mini_scene != null
