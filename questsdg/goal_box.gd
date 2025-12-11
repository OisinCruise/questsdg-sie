extends Area3D

@export var image:Texture 

var inside:bool = false

var mats = []

@export var goal:int = 1


var ani_box

func set_texture(mesh:MeshInstance3D):
	var mat:StandardMaterial3D = mesh.get_surface_override_material(0)
	mat = mat.duplicate()
	mat.albedo_texture = image
	mesh.set_surface_override_material(0, mat)
	mats.push_back(mat)
	
var left:Hand
var right:Hand

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	#var t = Thread.new()
	#t.start(load_ani_box)
	#
	set_texture($scaler/front)
	set_texture($scaler/back)
	set_texture($scaler/left)
	set_texture($scaler/right)
	set_texture($scaler/top)
	set_texture($scaler/bot)
	
	left = $"../../../XROrigin3D/left"
	right = $"../../../XROrigin3D/right"
	monitoring = false
	pass # Replace with function body.
	

var fade_out_tween:Tween = null

func make_invisible():
	fade_out_tween = null
	monitoring = false        # Stops detecting other bodies entering/exiting
	monitorable = false 
	
	ani_box = get_parent().ani_boxes[goal - 1]
	ani_box.position = position
	ani_box.rotation = rotation
	ani_box.visible = true
	# ani_box.get_node
	ani_box.bounce_in()
	Talo.events.track("Goal " + str(goal) + " thumbs up")
	Talo.events.flush()
	inside = false
	deactivate()
	# get_parent().add_child(ani_box)
	
	
func fade_out():
	if fade_out_tween:
		return
	else:
		scale = big_scale
		# fade_out_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
		fade_out_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
		fade_out_tween.tween_property(self, "scale", Vector3.ZERO,2)
		
		
		# $selected_sound.play()
		#for mat in mats:
			#fade_out_tween.tween_property(mat, "albedo_color:a", 0.0, 2.0)
			#fade_out_tween.set_parallel(true)
			## Optional: Hide the mesh when fade completes
		fade_out_tween.finished.connect(make_invisible)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# rotate_y(delta)
	# rotate_x(delta)
	
	if inside && hand.selected:
		fade_out()		
	pass

var hand

func _on_area_entered(area: Area3D) -> void:	
	if area.name.contains("hand"):
		if ! area.get_parent().selected:
			play_sound()
			hand = area.get_parent()
			var t = create_tween() \
				.set_ease(Tween.EASE_IN_OUT) \
				.set_trans(Tween.TRANS_QUINT)
			scale = Vector3.ONE
			t.tween_property(self, "scale", big_scale, 1)
			inside = true
	pass # Replace with function body.

var big_scale = Vector3(1.25, 1.25, 1.25)

var can_play = true

func play_sound():
	if can_play:
		$AudioStreamPlayer3D.pitch_scale = randf_range(0.8, 1.2)
		$AudioStreamPlayer3D.play()
		can_play = false
		await get_tree().create_timer(0.1).timeout
		can_play = true
		
	
func deactivate():
	visible = false
	$".".monitoring = false

func _on_area_exited(area: Area3D) -> void:
	if fade_out_tween:
		return
	if scale == Vector3.ONE:
		return
	if area.name.contains("hand"):
		play_sound()
		hand = null
		var t = create_tween() \
			.set_ease(Tween.EASE_IN_OUT) \
			.set_trans(Tween.TRANS_QUINT)
		scale = big_scale
		t.tween_property(self, "scale", Vector3.ONE, 1)
		inside = false

	pass # Replace with function body.
