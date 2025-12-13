class_name XRGrabbable
extends RigidBody3D

signal grabbed(hand: Hand)
signal released(hand: Hand)
signal placed_in_target(target: Node3D)

@export var grab_distance: float = 0.15
@export var highlight_material: Material = null

var is_grabbed: bool = false
var grabbing_hand: Hand = null
var original_parent: Node = null
var original_freeze: bool = false

func _ready() -> void:
	original_freeze = freeze
	add_to_group("grabbable")
	_setup_detection_area()

func _setup_detection_area() -> void:
	if not has_node("GrabArea"):
		var area = Area3D.new()
		area.name = "GrabArea"
		area.collision_layer = 0
		area.collision_mask = 1
		var shape = CollisionShape3D.new()
		var sphere = SphereShape3D.new()
		sphere.radius = grab_distance
		shape.shape = sphere
		area.add_child(shape)
		add_child(area)
		area.area_entered.connect(_on_grab_area_entered)
		area.area_exited.connect(_on_grab_area_exited)

func _on_grab_area_entered(area: Area3D) -> void:
	if area.name.contains("hand"):
		var potential_hand = area.get_parent()
		if potential_hand is Hand:
			potential_hand.register_nearby_grabbable(self)

func _on_grab_area_exited(area: Area3D) -> void:
	if area.name.contains("hand"):
		var potential_hand = area.get_parent()
		if potential_hand is Hand:
			potential_hand.unregister_nearby_grabbable(self)

func _physics_process(_delta: float) -> void:
	if is_grabbed and grabbing_hand:
		global_position = grabbing_hand.global_position

func try_grab(hand: Hand) -> bool:
	if is_grabbed:
		return false

	if not hand.pinching:
		return false

	var distance = global_position.distance_to(hand.global_position)
	if distance > grab_distance:
		return false

	_do_grab(hand)
	return true

func _do_grab(hand: Hand) -> void:
	is_grabbed = true
	grabbing_hand = hand
	original_freeze = freeze
	freeze = true

	if highlight_material:
		_apply_highlight(false)

	emit_signal("grabbed", hand)

func release() -> void:
	if not is_grabbed:
		return

	var released_hand = grabbing_hand
	is_grabbed = false
	grabbing_hand = null
	freeze = original_freeze

	emit_signal("released", released_hand)

func force_release() -> void:
	release()

func _apply_highlight(highlighted: bool) -> void:
	if not highlight_material:
		return
	pass

func on_placed_in_target(target: Node3D) -> void:
	emit_signal("placed_in_target", target)
