extends Label3D

@export var speed = 1

var theta = 0
var amp = 0.01

func _physics_process(delta: float) -> void:
	position.y = sin(theta) * amp
	theta += delta * speed
