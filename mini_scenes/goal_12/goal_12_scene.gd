extends MiniScene

@export var waste_items: Array[PackedScene] = []
@export var spawn_count: int = 10
@export var spawn_interval: float = 3.0

var items_sorted: int = 0
var items_correct: int = 0
var spawn_timer: Timer = null
var spawn_point: Node3D = null

@onready var recycling_bin: TargetZone = $Bins/RecyclingBin if has_node("Bins/RecyclingBin") else null
@onready var compost_bin: TargetZone = $Bins/CompostBin if has_node("Bins/CompostBin") else null
@onready var landfill_bin: TargetZone = $Bins/LandfillBin if has_node("Bins/LandfillBin") else null

func setup_scene() -> void:
	goal_number = 12

	if has_node("SpawnPoint"):
		spawn_point = $SpawnPoint

	_connect_bins()

func _connect_bins() -> void:
	if recycling_bin:
		recycling_bin.object_placed.connect(_on_item_sorted)
	if compost_bin:
		compost_bin.object_placed.connect(_on_item_sorted)
	if landfill_bin:
		landfill_bin.object_placed.connect(_on_item_sorted)

func start_scene() -> void:
	super.start_scene()

	items_sorted = 0
	items_correct = 0

	if sustainabot:
		sustainabot.play_gibberish()

	await get_tree().create_timer(2.0).timeout

	if is_active:
		_start_spawning()

func _start_spawning() -> void:
	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_spawn_waste_item)
	add_child(spawn_timer)
	spawn_timer.start()

	_spawn_waste_item()

func _spawn_waste_item() -> void:
	if items_sorted >= spawn_count:
		if spawn_timer:
			spawn_timer.stop()
		return

	if waste_items.size() == 0:
		push_warning("Goal 12: No waste items configured")
		return

	var item_scene = waste_items[randi() % waste_items.size()]
	var item = item_scene.instantiate()
	add_child(item)

	if spawn_point:
		item.global_position = spawn_point.global_position
	else:
		item.global_position = global_position + Vector3(0, 1.5, -1.0)

	item.global_position += Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))

func _on_item_sorted(object: XRGrabbable, correct: bool) -> void:
	items_sorted += 1

	if correct:
		items_correct += 1
		report_action(true)
	else:
		report_action(false)

	if items_sorted >= spawn_count:
		_finish_task()

func _finish_task() -> void:
	if spawn_timer:
		spawn_timer.stop()
		spawn_timer.queue_free()
		spawn_timer = null

	var success_rate = float(items_correct) / float(spawn_count)
	var success = success_rate >= 0.7

	if sustainabot:
		if success:
			sustainabot.set_state("commending")
		else:
			sustainabot.set_state("berating")

	await get_tree().create_timer(2.0).timeout

	Talo.events.track("Goal 12 items sorted", {
		"correct": str(items_correct),
		"total": str(spawn_count),
		"accuracy": str(success_rate)
	})

	complete_task(success)

func end_scene() -> void:
	if spawn_timer:
		spawn_timer.stop()
		spawn_timer.queue_free()
		spawn_timer = null

	super.end_scene()
