extends Node2D


@onready var target = $target
@onready var character = $character
var maxSpeed = 3.0
var maxRotation = PI
var radius = 50.0
var time_to_target = 9.0

var targets = [Vector2(30, 30), Vector2(1270, 30), Vector2(1270, 1470), Vector2(30, 1470)]
var target_ptr = 0


func get_steering_seek() -> KinematicSteeringOutput:
	var steering = KinematicSteeringOutput.new()
	steering.velocity = target.position - character.position
	steering.velocity = steering.velocity.normalized() * maxSpeed
	return steering
	
func get_steering_arrive() -> KinematicSteeringOutput:
	var steering = KinematicSteeringOutput.new()
	steering.velocity = targets[target_ptr] - target.position
	if steering.velocity.length() < radius:
		steering.velocity = Vector2.ZERO
		target_ptr = target_ptr + 1 if target_ptr < targets.size() - 1 else 0
		print(target_ptr)
		return steering
	
	steering.velocity = steering.velocity / time_to_target
	if steering.velocity.length() > maxSpeed:
		steering.velocity.normalized()
		steering.velocity *= maxSpeed
	return steering

func orintation_vector(rotation: float) -> Vector2:
	return Vector2(-sin(rotation), cos(rotation))

func get_new_orientation(current_orientation, velocity):
	return atan2(-target.position.x, target.position.y)

func get_steering_wandering() -> KinematicSteeringOutput:
	var steering = KinematicSteeringOutput.new()
	steering.velocity = orintation_vector(target.rotation) * maxSpeed
	steering.rotation = maxRotation * (randf() - randf())
	return steering
	
func _process(delta: float) -> void:
	var steering = get_steering_arrive()
	#print(steering.velocity)
	target.velocity += steering.velocity * delta
	target.rotation += steering.rotation * delta
	target.move_and_slide()
	
	#var steering1 = get_steering_arrive()
	#character.velocity += steering1.velocity * delta
	#character.move_and_slide()
	#print(character.velocity)
	
	
	
	
	
	
