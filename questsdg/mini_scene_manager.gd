class_name MiniSceneManager
extends Node3D

signal scene_opened(goal_number: int)
signal scene_closed(goal_number: int)
signal task_completed(goal_number: int, success: bool)

var current_mini_scene: MiniScene = null
var xr_origin: XROrigin3D = null
var is_transitioning: bool = false
var maps_node: Node3D = null
var maps_fade_tween: Tween = null
var last_opened_scene: int = -1
var scene_switch_cooldown: float = 0.0

func _ready() -> void:
	xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if not xr_origin:
		var origins = get_tree().get_nodes_in_group("xr_origin")
		if origins.size() > 0:
			xr_origin = origins[0]

	# Find maps node for fade effect during mini-scenes
	await get_tree().process_frame
	maps_node = get_tree().root.get_node_or_null("cubes_scene/tu dub/maps")
	if not maps_node:
		maps_node = get_tree().root.get_node_or_null("cubes_scene_earlier/tu dub/maps")

func _process(delta: float) -> void:
	# Count down the scene switch cooldown
	if scene_switch_cooldown > 0:
		scene_switch_cooldown -= delta

func open_mini_scene(goal_number: int) -> void:
	# If already transitioning, ignore (prevents race conditions)
	if is_transitioning:
		print("MiniSceneManager: Already transitioning, ignoring request for scene %d" % goal_number)
		return

	# Check cooldown to prevent rapid re-triggering
	if scene_switch_cooldown > 0:
		print("MiniSceneManager: Cooldown active (%.2fs remaining), ignoring request for scene %d" % [scene_switch_cooldown, goal_number])
		return

	# If trying to open the same scene that was just opened/interrupted, ignore
	if last_opened_scene == goal_number and scene_switch_cooldown == 0:
		print("MiniSceneManager: Ignoring duplicate request for scene %d" % goal_number)
		scene_switch_cooldown = 2.0  # Set longer cooldown to prevent spam
		return

	# If a scene is currently active, close it first
	if current_mini_scene:
		_interrupt_current_scene()

	is_transitioning = true
	last_opened_scene = goal_number
	scene_switch_cooldown = 1.5  # Cooldown to prevent immediate re-triggering

	var scene_path = "res://mini_scenes/goal_%d/goal_%d_scene.tscn" % [goal_number, goal_number]

	if not ResourceLoader.exists(scene_path):
		push_warning("Mini-scene not found: " + scene_path)
		is_transitioning = false
		return

	# Fade out maps before opening mini-scene
	_fade_out_maps()

	var scene_res = load(scene_path)
	if scene_res:
		current_mini_scene = scene_res.instantiate()
		add_child(current_mini_scene)

		# Position scene relative to XR origin
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

	# Reset last opened scene after a proper close (not an interrupt)
	last_opened_scene = -1
	scene_switch_cooldown = 0.5  # Small cooldown after close

	# Fade maps back in after mini-scene closes
	_fade_in_maps()

	emit_signal("scene_closed", goal_num)
	emit_signal("task_completed", goal_num, success)

	Talo.events.track("Goal %d task completed" % goal_num, {"success": str(success)})
	Talo.events.flush()

	is_transitioning = false

func _on_task_completed(success: bool) -> void:
	close_current_scene(success)

func is_in_mini_scene() -> bool:
	return current_mini_scene != null

func _interrupt_current_scene() -> void:
	if not current_mini_scene:
		return

	var goal_num = current_mini_scene.goal_number
	var scene_to_close = current_mini_scene

	# Clear reference FIRST to prevent any callbacks from accessing it
	current_mini_scene = null

	# Disconnect task_completed signal to prevent loop
	if scene_to_close.task_completed.is_connected(_on_task_completed):
		scene_to_close.task_completed.disconnect(_on_task_completed)

	# Stop any ongoing processes
	scene_to_close.is_active = false

	# Kill any active tweens to prevent callbacks
	if scene_to_close.fade_tween:
		scene_to_close.fade_tween.kill()

	# Immediately clean up
	scene_to_close.queue_free()

	# Emit signal for cleanup
	emit_signal("scene_closed", goal_num)
	print("MiniSceneManager: Interrupted scene %d" % goal_num)

func _fade_out_maps() -> void:
	if not maps_node:
		return

	if maps_fade_tween and maps_fade_tween.is_running():
		maps_fade_tween.kill()

	maps_fade_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	maps_fade_tween.tween_property(maps_node, "scale", Vector3.ZERO, 1.0)
	maps_fade_tween.tween_callback(func(): maps_node.visible = false)

func _fade_in_maps() -> void:
	if not maps_node:
		return

	if maps_fade_tween and maps_fade_tween.is_running():
		maps_fade_tween.kill()

	maps_node.visible = true
	maps_node.scale = Vector3.ZERO
	maps_fade_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	maps_fade_tween.tween_property(maps_node, "scale", Vector3.ONE, 1.0)
