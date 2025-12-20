# SteeringAgent2D.gd
extends CharacterBody2D
class_name SteeringAgent2D

# ----------- Tuning -----------
@export var max_speed: float = 220.0
@export var max_accel: float = 900.0

# Arrive
@export var arrive_radius: float = 6.0
@export var slow_radius: float  = 12.0

# Separation
@export var separation_radius: float = 150.0
@export var separation_strength: float = 500.0

# Obstacle Avoid
@export var avoid_ray_length: float = 72.0
@export var avoid_side_angle_deg: float = 25.0
@export var avoid_force: float = 1000.0
@export var avoid_normal_bias: float = 0.65  # 0..1 (0=lateral only, 1=normal only)

# Blending weights
@export var w_obstacle := 1.0
@export var w_separation := 2.5
@export var w_arrive := 0.5
@export var w_seek := 1.0  # set >0 if you also want raw seek

# Target used by Seek/Arrive
@export var target: NodePath

# ----------- Runtime -----------
var _target_pos: Vector2
var _rc_fwd: RayCast2D
var _rc_left: RayCast2D
var _rc_right: RayCast2D
var _velocity_line: Line2D

func _ready() -> void:
	# Cache target pos if a NodePath was provided
	if target != NodePath():
		var t = get_node_or_null(target)
		if t:
			_target_pos = t.global_position

	# Build raycasts for obstacle avoidance (local +X is "forward" for rays)
	_rc_fwd  = _make_ray(0.0)
	_rc_left = _make_ray(-deg_to_rad(avoid_side_angle_deg))
	_rc_right= _make_ray( deg_to_rad(avoid_side_angle_deg))

	# ensure we're in agents2d group for separation (you can add via editor too)
	if not is_in_group("agents2d"):
		add_to_group("agents2d")
	
	# Create velocity visualization line
	_velocity_line = Line2D.new()
	_velocity_line.z_index = 5  # Draw behind sprite
	_velocity_line.width = 5.0
	_velocity_line.default_color = Color.GREEN
	add_child(_velocity_line)

func _make_ray(yaw: float) -> RayCast2D:
	var rc := RayCast2D.new()
	rc.target_position = Vector2(avoid_ray_length, 0.0)   # forward in rc's local space
	rc.rotation = yaw                                     # offset relative to this node
	rc.hit_from_inside = true
	rc.collide_with_areas = true
	rc.collide_with_bodies = true
	add_child(rc)
	rc.enabled = true
	return rc

func _physics_process(delta: float) -> void:
	# If target node moves, refresh
	if target != NodePath():
		var t = get_node_or_null(target)
		if t:
			_target_pos = t.global_position

	var acc := Vector2.ZERO
	#acc += obstacle_avoid() * w_obstacle
	acc += separation() * w_separation
	acc += arrive(_target_pos) * w_arrive
	#acc += seek(_target_pos) * w_seek

	# Clamp accel & integrate
	if acc.length() > max_accel:
		acc = acc.normalized() * max_accel
	velocity += acc * delta
	velocity = velocity.limit_length(max_speed)

	_face_velocity(delta)
	move_and_slide()
	
	# Update velocity visualization
	if velocity.length() > 0.1:
		var scale_factor = 0.2  # Scale down the velocity visualization
		var start = Vector2.ZERO
		var end = velocity * scale_factor
		
		var arrow_size = 20.0
		var arrow_dir = (end - start).normalized()
		var perp = Vector2(-arrow_dir.y, arrow_dir.x)
		var arrow_point = end - arrow_dir * arrow_size
		
		_velocity_line.clear_points()
		_velocity_line.add_point(start)
		_velocity_line.add_point(end)
		_velocity_line.add_point(arrow_point + perp * arrow_size * 0.5)
		_velocity_line.add_point(end)
		_velocity_line.add_point(arrow_point - perp * arrow_size * 0.5)
	else:
		_velocity_line.clear_points()

# ---------------- Behaviors ----------------

func seek(tpos: Vector2) -> Vector2:
	var desired := tpos - global_position
	if desired.length() == 0.0:
		return Vector2.ZERO
	desired = desired.normalized() * max_speed
	return desired - velocity

func arrive(tpos: Vector2) -> Vector2:
	var to_t := tpos - global_position
	var dist := to_t.length()

	if dist < arrive_radius:
		# Strong brake to stop drift
		if get_physics_process_delta_time() > 0.0:
			return -velocity / get_physics_process_delta_time()
		else:
			return -velocity

	var speed := 0.0
	if dist > slow_radius:
		speed = max_speed
	else:
		if slow_radius > 0.0:
			speed = max_speed * dist / slow_radius
		else:
			speed = 0.0

	var desired := Vector2.ZERO
	if dist > 0.001:
		desired = to_t.normalized() * speed
	return desired - velocity

func separation() -> Vector2:
	var force := Vector2.ZERO
	var my_pos := global_position
	for agent in get_tree().get_nodes_in_group("agents2d"):
		if agent == self:
			continue
		if not agent is SteeringAgent2D:
			continue
		var to_me = my_pos - agent.global_position
		var d = to_me.length()
		if d > 0.001 and d < separation_radius:
			# Use squared distance for stronger push when very close
			var strength = separation_strength / (d * d)
			force += to_me.normalized() * strength
	return force

func obstacle_avoid() -> Vector2:
	# Check the three rays. If any collides, steer away.
	var out := _avoid_from_ray(_rc_fwd)
	out += _avoid_from_ray(_rc_left) * 0.7
	out += _avoid_from_ray(_rc_right) * 0.7
	return out

func _avoid_from_ray(rc: RayCast2D) -> Vector2:
	if not rc.is_colliding():
		return Vector2.ZERO
	var n := rc.get_collision_normal().normalized()
	if n.length() < 0.001:
		return Vector2.ZERO

	# Lateral (slide) direction is normal rotated 90°
	var lateral := Vector2(-n.y, n.x).normalized()

	# Blend pushing off the surface normal + a lateral slide
	var steering := (n * avoid_normal_bias + lateral * (1.0 - avoid_normal_bias)).normalized() * avoid_force

	# If we're already moving into a wall, bias stronger
	if velocity.dot(-n) > 0.0:
		steering *= 1.25
	return steering

# ---------------- Helpers ----------------

func _face_velocity(delta: float) -> void:
	if velocity.length() < 0.01:
		return
	var target_angle := velocity.angle()
	rotation = lerp_angle(rotation, target_angle, clamp(10.0 * delta, 0.0, 1.0))
