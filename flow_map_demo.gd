extends Node2D

@export var spawn_batch_size: int = 30  # Number of guys to spawn per batch
@export var spawn_interval: float = 1.5  # Seconds between spawn batches
@export var target_area_height: float = 1000.0  # Height of target area on right side
@export var guy_scene: PackedScene = preload("res://guy.tscn")
@export var flow_map_cell_size: float = 80.0  # Grid cell size (should be 1.5-2x agent collision radius)
@export var repulsion_radius: float = 100.0  # How far agents affect flow
@export var repulsion_strength: float = 2.5  # Strength of repulsion
@export var obstacle_repulsion_radius: float = 300.0  # How far obstacles affect flow
@export var obstacle_repulsion_strength: float = 85.0  # Strength of obstacle repulsion
@export var front_repulsion_multiplier: float = 1.5  # Multiplier for front side (strongest)
@export var top_bottom_repulsion_multiplier: float = 0.5  # Multiplier for top/bottom sides (weaker)
@export var back_repulsion_multiplier: float = 0.2  # Multiplier for back side (weakest)
@export var flow_smoothing: float = 0.5  # Flow map smoothing (0-1, higher = more smoothing)
@export var show_flow_map: bool = true  # Show flow map visualization
@export var show_grid_lines: bool = false  # Show grid lines in visualization
@export var vector_scale: float = 0.3  # Scale of flow vectors in visualization
@export var show_node_directions: bool = true  # Show actual direction each node is using
@export var flow_map_weight: float = 0.5  # Weight of flow map direction (0-1)
@export var direct_seek_weight: float = 0.5  # Weight of direct seek to target (0-1)

var guys: Dictionary = {}  # Dictionary to track guys: {guy_node: {speed: float, target: Vector2}}
var flow_map: FlowMap
var obstacle: StaticBody2D  # The obstacle in the center
var spawn_timer: Timer  # Timer for batch spawning
var agent_count_label: Label  # Label showing current agent count

func _ready():
	var viewport = get_viewport()
	var window_size = viewport.get_visible_rect().size
	
	# Initialize flow map
	# Note: Grid cell size should be 1.5-2x the agent collision radius
	# Agent collision: radius=36, so cell_size should be 54-72px minimum
	# Using 80px for better stability
	flow_map = FlowMap.new()
	flow_map.initialize(window_size, flow_map_cell_size)
	flow_map.repulsion_radius = repulsion_radius
	flow_map.repulsion_strength = repulsion_strength
	flow_map.obstacle_repulsion_radius = obstacle_repulsion_radius
	flow_map.obstacle_repulsion_strength = obstacle_repulsion_strength
	flow_map.front_repulsion_multiplier = front_repulsion_multiplier
	flow_map.top_bottom_repulsion_multiplier = top_bottom_repulsion_multiplier
	flow_map.back_repulsion_multiplier = back_repulsion_multiplier
	flow_map.smoothing_factor = flow_smoothing
	flow_map.show_visualization = show_flow_map
	flow_map.show_grid_lines = show_grid_lines
	flow_map.vector_scale = vector_scale
	add_child(flow_map)
	
	# Create obstacle in center of screen
	create_obstacle(window_size)
	
	# Create and start spawn timer
	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.one_shot = false  # Repeat indefinitely
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)
	spawn_timer.start()
	
	# Spawn initial batch
	spawn_batch(window_size)
	
	# Create agent count label
	create_agent_count_label(window_size)

func create_agent_count_label(window_size: Vector2):
	# Create a CanvasLayer for UI elements
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
	# Create label
	agent_count_label = Label.new()
	agent_count_label.text = "Agents: 0"
	agent_count_label.add_theme_font_size_override("font_size", 24)
	agent_count_label.modulate = Color.WHITE
	
	# Position in top-right corner with padding
	var padding = 10.0
	agent_count_label.position = Vector2(window_size.x - 200.0, padding)
	
	canvas_layer.add_child(agent_count_label)

func spawn_batch(window_size: Vector2):
	# Spawn a batch of guys
	for i in range(spawn_batch_size):
		spawn_guy(window_size)

func _on_spawn_timer_timeout():
	# Called when spawn timer fires
	var viewport = get_viewport()
	var window_size = viewport.get_visible_rect().size
	spawn_batch(window_size)

func create_obstacle(window_size: Vector2):
	# Create a 300x300 obstacle in the center of the screen
	var obstacle_size = Vector2(300, 300)
	var obstacle_center = window_size * 0.5
	var obstacle_pos = obstacle_center - obstacle_size * 0.5  # Top-left corner
	
	# Create StaticBody2D for obstacle
	obstacle = StaticBody2D.new()
	obstacle.position = obstacle_pos
	obstacle.name = "Obstacle"
	obstacle.collision_layer = 1  # Set collision layer
	obstacle.collision_mask = 0   # Obstacles don't need to detect collisions
	
	# Create collision shape (no offset - shape starts at position)
	var collision_shape = CollisionShape2D.new()
	var rectangle_shape = RectangleShape2D.new()
	rectangle_shape.size = obstacle_size
	collision_shape.shape = rectangle_shape
	collision_shape.position = obstacle_size * 0.5  # Center of rectangle relative to obstacle position
	obstacle.add_child(collision_shape)
	
	# Create visual representation (matches collision bounds exactly)
	var color_rect = ColorRect.new()
	color_rect.size = obstacle_size
	color_rect.position = Vector2.ZERO  # Start at obstacle position
	color_rect.color = Color(1.0, 0.0, 0.0, 0.5)  # Semi-transparent red
	obstacle.add_child(color_rect)
	
	add_child(obstacle)

func spawn_guy(window_size: Vector2):
	# Create instance of guy at x=0 and random y-position
	var start_y = randf() * window_size.y
	var start_pos = Vector2(0, start_y)
	
	# Target area on opposite side, centered at half window height
	var target_area_center_y = window_size.y * 0.5
	var target_area_min_y = target_area_center_y - target_area_height * 0.5
	var target_area_max_y = target_area_center_y + target_area_height * 0.5
	
	# Store target as area (for checking if reached)
	var target_area = {
		"x": window_size.x,
		"min_y": target_area_min_y,
		"max_y": target_area_max_y
	}
	
	# Random speed between 200-400
	var speed = randf_range(200.0, 400.0)
	
	# Instantiate the guy
	var guy = guy_scene.instantiate()
	guy.position = start_pos
	add_child(guy)
	
	# Store guy data
	guys[guy] = {
		"speed": speed,
		"target_area": target_area
	}

func _physics_process(_delta):
	var viewport = get_viewport()
	var window_size = viewport.get_visible_rect().size
	
	# Collect all agent positions for flow map recalculation
	var agent_positions = []
	for guy in guys.keys():
		if is_instance_valid(guy):
			agent_positions.append(guy.position)
	
	# Update visualization settings (in case they changed in editor)
	flow_map.show_visualization = show_flow_map
	flow_map.show_grid_lines = show_grid_lines
	flow_map.vector_scale = vector_scale
	
	# Update spawn timer interval (in case it changed in editor)
	if is_instance_valid(spawn_timer):
		spawn_timer.wait_time = spawn_interval
	
	# Collect obstacle information for flow map
	var obstacles = []
	if is_instance_valid(obstacle):
		# Store obstacle as rectangle: {position: Vector2, size: Vector2}
		# Use global_position to get world coordinates
		var obstacle_global_pos = obstacle.global_position
		obstacles.append({
			"position": obstacle_global_pos,
			"size": Vector2(300, 300)
		})
	
	# Recalculate flow map every frame based on current agent positions and obstacles
	# Goal area must match the target_area used by agents
	# This ensures flow map guides agents to the same area they're targeting
	var target_area_center_y = window_size.y * 0.5
	var goal_area = {
		"x": window_size.x,
		"min_y": target_area_center_y - target_area_height * 0.5,
		"max_y": target_area_center_y + target_area_height * 0.5
	}
	flow_map.recalculate(agent_positions, goal_area, obstacles)
	
	# Track guys to remove (reached target)
	var guys_to_remove = []
	
	# Update all guys using flow map
	for guy in guys.keys():
		if not is_instance_valid(guy):
			guys_to_remove.append(guy)
			continue
		
		var guy_data = guys[guy]
		var speed = guy_data["speed"]
		var target_area = guy_data["target_area"]
		
		# Check if reached target area - remove once they've reached the right side (x position)
		# Add a small buffer zone to prevent jittering at the edge
		var removal_buffer = 10.0  # Remove agents slightly before they reach the exact edge
		var reached_target = guy.position.x >= (target_area["x"] - removal_buffer)
		
		# Get flow direction from flow map (crowd avoidance)
		# The flow map already handles repulsion from other agents
		var flow_direction = flow_map.get_flow_vector(guy.position)
		
		# If already at target x position, stop moving completely (they'll be removed)
		# Otherwise, blend flow map with direct seek
		var final_direction = flow_direction
		if not reached_target:
			# Get direct direction to target area (closest point on target area)
			var target_x = target_area["x"]
			var target_y = clamp(guy.position.y, target_area["min_y"], target_area["max_y"])
			var target_point = Vector2(target_x, target_y)
			var target_direction = (target_point - guy.position)
			var distance_to_target = target_direction.length()
			
			# Blend flow map (crowd avoidance) with direct seek (target guidance)
			# Flow map provides crowd avoidance, direct seek provides target guidance
			if distance_to_target > 0.001:
				var total_weight = flow_map_weight + direct_seek_weight
				var flow_weight = flow_map_weight / total_weight if total_weight > 0.0 else 0.5
				var seek_weight = direct_seek_weight / total_weight if total_weight > 0.0 else 0.5
				var normalized_target_dir = target_direction.normalized()
				final_direction = (flow_direction * flow_weight + normalized_target_dir * seek_weight).normalized()
		
		# Move using blended direction
		if not reached_target:
			# Clamp position to prevent overshooting the target
			var target_x = target_area["x"]
			if guy.position.x < target_x:
				# Set velocity based on blended direction
				guy.velocity = final_direction * speed
				# Store final direction for visualization
				if show_node_directions:
					guy.set_meta("final_direction", final_direction)
				# Use move_and_slide to handle collisions
				guy.move_and_slide()
				
				# Clamp position after movement to prevent overshooting
				if guy.position.x > target_x:
					guy.position.x = target_x
			else:
				# Already past target, stop moving
				guy.velocity = Vector2.ZERO
		else:
			# Reached target - stop all movement to prevent jittering
			guy.velocity = Vector2.ZERO
			guys_to_remove.append(guy)
	
	# Remove guys that reached target (no respawning)
	for guy in guys_to_remove:
		if is_instance_valid(guy):
			guy.queue_free()
		guys.erase(guy)
	
	# Update agent count label
	if is_instance_valid(agent_count_label):
		var valid_agent_count = 0
		for guy in guys.keys():
			if is_instance_valid(guy):
				valid_agent_count += 1
		agent_count_label.text = "Agents: " + str(valid_agent_count)
		
		# Update label position if window size changed
		var label_padding = 10.0
		agent_count_label.position = Vector2(window_size.x - 200.0, label_padding)
	
	# Draw node direction visualization and target area
	queue_redraw()

func _draw():
	var viewport = get_viewport()
	var window_size = viewport.get_visible_rect().size
	
	# Draw target area lines
	var target_area_center_y = window_size.y * 0.5
	var target_area_min_y = target_area_center_y - target_area_height * 0.5
	var target_area_max_y = target_area_center_y + target_area_height * 0.5
	var target_x = window_size.x
	
	var target_area_color = Color(1.0, 1.0, 0.0, 0.8)  # Yellow for target area
	var line_width = 3.0
	
	# Draw vertical line at target x position
	draw_line(Vector2(target_x, 0), Vector2(target_x, window_size.y), target_area_color, line_width)
	
	# Draw horizontal lines marking top and bottom of target area
	draw_line(Vector2(target_x - 50.0, target_area_min_y), Vector2(target_x, target_area_min_y), target_area_color, line_width)
	draw_line(Vector2(target_x - 50.0, target_area_max_y), Vector2(target_x, target_area_max_y), target_area_color, line_width)
	
	# Only draw node directions if enabled
	if not show_node_directions:
		return
	
	# Draw actual direction each node is using
	var arrow_length = 30.0
	var arrow_head_size = 10.0
	var node_direction_color = Color(0.0, 0.0, 1.0, 0.8)  # Blue for node directions
	
	for guy in guys.keys():
		if not is_instance_valid(guy):
			continue
		
		var final_dir = guy.get_meta("final_direction", Vector2.ZERO)
		if final_dir.length() < 0.01:
			continue
		
		var node_pos = guy.position
		var arrow_dir = final_dir.normalized()
		var arrow_end = node_pos + arrow_dir * arrow_length
		
		# Draw arrow line
		draw_line(node_pos, arrow_end, node_direction_color, 2.0)
		
		# Draw arrow head
		var perp = Vector2(-arrow_dir.y, arrow_dir.x)
		var arrow_point1 = arrow_end - arrow_dir * arrow_head_size + perp * arrow_head_size * 0.5
		var arrow_point2 = arrow_end - arrow_dir * arrow_head_size - perp * arrow_head_size * 0.5
		draw_line(arrow_end, arrow_point1, node_direction_color, 2.0)
		draw_line(arrow_end, arrow_point2, node_direction_color, 2.0)
