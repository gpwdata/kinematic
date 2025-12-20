extends CharacterBody2D

var target: CharacterBody2D
var max_speed = 90
var time_to_target = 0.5
var radius = 40.0

var max_prediction = 1.0

func  _ready() -> void:
	global_position = Vector2(1200.0, 800.0)
	

func  seek(target_pos: Vector2) -> void:
	var to_vect =  target_pos - global_position
	var distance = to_vect.length()
	if distance < radius:
		return
	velocity = to_vect
	#velocity = velocity / time_to_target
	if velocity.length() > max_speed:
		velocity = to_vect.normalized() * max_speed
	rotation = atan2(velocity.x, -velocity.y)
	move_and_slide()

func  _physics_process(delta: float) -> void:
	var direction = target.global_position - global_position
	var distance = direction.length()
	var speed = target.velocity.length()
	var prediction = 0
	if speed <= distance / max_prediction:
		prediction = max_prediction
	else:
		prediction = distance / speed
	seek(target.global_position + (target.velocity * prediction))
		
