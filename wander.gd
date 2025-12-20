extends CharacterBody2D


var max_speed = 200.0
var max_rotation = 2.09

func  _ready() -> void:
	randomize()
	position = Vector2(500.0, 500.0)

func _physics_process(delta: float) -> void:
	# 1) Small random change in orientation
	var random_binomial := randf() - randf() # [-1, 1]
	rotation += random_binomial * max_rotation * delta

	# 2) Convert orientation (rotation) to direction **after** updating it
	var dir: Vector2 = Vector2.RIGHT.rotated(rotation)

	# 3) Set velocity and move
	velocity = dir * max_speed
	move_and_slide()
