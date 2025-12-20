extends CharacterBody2D


var target: CharacterBody2D
var max_speed = 250
var time_to_target = 0.5
var radius = 40.0

func  _ready() -> void:
	pass

func  _physics_process(delta: float) -> void:
	var target_pos = target.global_position
	var to_vect =  target_pos - global_position
	var distance = to_vect.length()
	if distance < radius:
		return
	velocity = to_vect
	velocity = velocity / time_to_target
	if velocity.length() > max_speed:
		velocity = to_vect.normalized() * max_speed
	rotation = atan2(velocity.x, -velocity.y)
	move_and_slide()
		
