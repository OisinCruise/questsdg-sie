extends Node3D

var player:TaloPlayer
var mini_scene_manager: MiniSceneManager = null

func _on_identified(player: TaloPlayer) -> void:
	self.player = player
	Talo.events.track("Player is identified!", {
	})
	Talo.events.flush()

func _ready() -> void:
	Talo.players.identify("Quest SDG", Talo.players.generate_identifier())
	Talo.players.identified.connect(_on_identified)

	_setup_mini_scene_manager()
	_connect_animated_boxes()

func _setup_mini_scene_manager() -> void:
	mini_scene_manager = MiniSceneManager.new()
	mini_scene_manager.name = "MiniSceneManager"
	add_child(mini_scene_manager)

	mini_scene_manager.scene_closed.connect(_on_mini_scene_closed)

func _connect_animated_boxes() -> void:
	var ani_goals = get_node_or_null("tu dub/ani_goals")
	if not ani_goals:
		push_warning("ani_goals node not found")
		return

	for child in ani_goals.get_children():
		if child.has_signal("mini_scene_requested"):
			child.mini_scene_requested.connect(_on_mini_scene_requested)

func _on_mini_scene_requested(goal_number: int) -> void:
	if mini_scene_manager:
		mini_scene_manager.open_mini_scene(goal_number)

func _on_mini_scene_closed(goal_number: int) -> void:
	var ani_goals = get_node_or_null("tu dub/ani_goals")
	if ani_goals:
		for child in ani_goals.get_children():
			if child.has_method("reset_mini_scene_trigger"):
				if child.goal_num1 == goal_number:
					child.reset_mini_scene_trigger()
	
