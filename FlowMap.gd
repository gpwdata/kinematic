class_name FlowMap
extends Node2D

# Grid properties
var cell_size: float = 32.0
var grid_width: int = 0
var grid_height: int = 0
var world_size: Vector2 = Vector2.ZERO

# Flow map data
var flow_vectors: Array[Array] = []  # Array[Array[Vector2]] - Final combined flow (static + congestion)
var previous_flow_vectors: Array[Array] = []  # For smoothing
var static_flow_vectors: Array[Array] = []  # Static flow (goal + obstacles) - calculated once
var congestion_vectors: Array[Array] = []  # Congestion map (agent repulsion) - updated every frame
var previous_congestion_vectors: Array[Array] = []  # For smoothing congestion

# Static map state
var static_map_calculated: bool = false
var cached_goal_area: Dictionary = {}
var cached_obstacles: Array = []

# Repulsion parameters
@export var repulsion_radius: float = 100.0  # How far agents affect flow
@export var repulsion_strength: float = 1.5  # Strength of repulsion
@export var obstacle_repulsion_radius: float = 100.0  # How far obstacles affect flow
@export var obstacle_repulsion_strength: float = 2.0  # Strength of obstacle repulsion (usually stronger)
@export var front_repulsion_multiplier: float = 1.5  # Multiplier for front side (strongest)
@export var top_bottom_repulsion_multiplier: float = 0.0  # Multiplier for top/bottom sides (weaker)
@export var back_repulsion_multiplier: float = 0.2  # Multiplier for back side (weakest)
@export var goal_weight: float = 2.0  # Weight for goal direction (higher = more goal bias)
@export var min_repulsion_distance: float = 5.0  # Minimum distance to avoid infinite forces
@export var smoothing_factor: float = 0.3  # How much to smooth flow map changes (0-1)

# Spatial optimization (optional)
var use_spatial_hashing: bool = true
var spatial_bucket_size: float = 128.0
var spatial_grid: Dictionary = {}

# Visualization
@export var show_visualization: bool = true
@export var vector_scale: float = 0.3  # Scale factor for vector arrows
@export var grid_line_color: Color = Color(1.0, 1.0, 1.0, 0.1)  # Subtle grid lines
@export var vector_color: Color = Color(0.0, 1.0, 0.0, 0.8)  # Green vectors
@export var show_grid_lines: bool = false  # Toggle grid lines

func initialize(world_size_param: Vector2, cell_size_param: float):
	world_size = world_size_param
	cell_size = cell_size_param
	
	# Calculate grid dimensions
	grid_width = ceil(world_size.x / cell_size) + 1
	grid_height = ceil(world_size.y / cell_size) + 1
	
	# Initialize flow vectors arrays
	flow_vectors.clear()
	previous_flow_vectors.clear()
	static_flow_vectors.clear()
	congestion_vectors.clear()
	previous_congestion_vectors.clear()
	
	for y in range(grid_height):
		var row: Array[Vector2] = []
		var prev_row: Array[Vector2] = []
		var static_row: Array[Vector2] = []
		var congestion_row: Array[Vector2] = []
		var prev_congestion_row: Array[Vector2] = []
		for x in range(grid_width):
			row.append(Vector2(1.0, 0.0))  # Default to right
			prev_row.append(Vector2(1.0, 0.0))
			static_row.append(Vector2(1.0, 0.0))
			congestion_row.append(Vector2.ZERO)  # Congestion starts at zero
			prev_congestion_row.append(Vector2.ZERO)
		flow_vectors.append(row)
		previous_flow_vectors.append(prev_row)
		static_flow_vectors.append(static_row)
		congestion_vectors.append(congestion_row)
		previous_congestion_vectors.append(prev_congestion_row)
	
	static_map_calculated = false
	cached_goal_area.clear()
	cached_obstacles.clear()
	
	print("FlowMap initialized: ", grid_width, "x", grid_height, " cells (", cell_size, "px each)")
	# Enable drawing and set z-index to draw behind agents
	z_index = -1
	if show_visualization:
		set_process(true)

func recalculate(agent_positions: Array, goal_area: Dictionary, obstacles: Array = []):
	# Check if static map needs recalculation (goal or obstacles changed)
	var static_changed = not static_map_calculated
	if not static_changed:
		# Compare goal area values
		if cached_goal_area.get("x", 0.0) != goal_area.get("x", 0.0) or \
		   cached_goal_area.get("min_y", 0.0) != goal_area.get("min_y", 0.0) or \
		   cached_goal_area.get("max_y", 0.0) != goal_area.get("max_y", 0.0):
			static_changed = true
		
		# Compare obstacles (simple length check - could be improved)
		if cached_obstacles.size() != obstacles.size():
			static_changed = true
		else:
			# Compare each obstacle (position and size)
			for i in range(obstacles.size()):
				var old_obs = cached_obstacles[i]
				var new_obs = obstacles[i]
				if old_obs.get("position", Vector2.ZERO) != new_obs.get("position", Vector2.ZERO) or \
				   old_obs.get("size", Vector2.ZERO) != new_obs.get("size", Vector2.ZERO):
					static_changed = true
					break
	
	if static_changed:
		_calculate_static_flow_map(goal_area, obstacles)
		cached_goal_area = goal_area.duplicate(true)
		cached_obstacles = obstacles.duplicate(true)
		static_map_calculated = true
	
	# Update congestion map (agent repulsion) - only cells near agents
	_update_congestion_map(agent_positions)
	
	# Combine static flow map with congestion map to get final flow vectors
	_combine_flow_maps()

func _calculate_static_flow_map(goal_area: Dictionary, obstacles: Array):
	# Calculate static flow map once (goal + obstacles, no agents)
	for y in range(grid_height):
		for x in range(grid_width):
			# Use cell center for more accurate calculations
			var cell_pos = grid_to_world(Vector2i(x, y)) + Vector2(cell_size * 0.5, cell_size * 0.5)
			static_flow_vectors[y][x] = _calculate_static_flow_vector(cell_pos, goal_area, obstacles)

func _calculate_static_flow_vector(cell_pos: Vector2, goal_area: Dictionary, obstacles: Array) -> Vector2:
	# 1. Goal direction (point toward goal area)
	var goal_x = goal_area["x"]
	var goal_min_y = goal_area["min_y"]
	var goal_max_y = goal_area["max_y"]
	
	# Find closest point on goal area to this cell
	var goal_y = clamp(cell_pos.y, goal_min_y, goal_max_y)
	var goal_point = Vector2(goal_x, goal_y)
	var to_goal = goal_point - cell_pos
	var goal_dir = Vector2(1.0, 0.0)  # Default to rightward
	if to_goal.length() > 0.001:
		goal_dir = to_goal.normalized()
	
	# 2. Calculate repulsion from obstacles (no agents)
	var obstacle_repulsion = Vector2.ZERO
	for obstacle in obstacles:
		obstacle_repulsion += _calculate_obstacle_repulsion(cell_pos, obstacle)
	
	# 3. Blend goal direction with obstacle repulsion
	var effective_goal_weight = goal_weight
	if obstacle_repulsion.length() > 2.0:
		effective_goal_weight = goal_weight * 0.5  # Reduce goal influence when near obstacles
	
	var flow = goal_dir * effective_goal_weight + obstacle_repulsion
	
	# 4. Normalize to get direction
	if flow.length() > 0.001:
		return flow.normalized()
	else:
		return goal_dir  # Fallback to goal direction

func _update_congestion_map(agent_positions: Array):
	# Clear spatial grid if using spatial hashing
	if use_spatial_hashing:
		spatial_grid.clear()
		_build_spatial_grid(agent_positions)
	
	# Store previous congestion vectors for smoothing
	for y in range(grid_height):
		for x in range(grid_width):
			previous_congestion_vectors[y][x] = congestion_vectors[y][x]
			# Reset congestion to zero (will be accumulated from agents)
			congestion_vectors[y][x] = Vector2.ZERO
	
	# Instead of iterating over all cells, iterate over agents and update nearby cells
	for agent_pos in agent_positions:
		_update_cells_near_agent(agent_pos)
	
	# Apply smoothing to congestion map
	if smoothing_factor > 0.0:
		var blend = 1.0 - smoothing_factor
		for y in range(grid_height):
			for x in range(grid_width):
				congestion_vectors[y][x] = previous_congestion_vectors[y][x].lerp(congestion_vectors[y][x], blend)

func _update_cells_near_agent(agent_pos: Vector2):
	# Find all grid cells within repulsion_radius of this agent
	var agent_grid_pos = world_to_grid(agent_pos)
	var radius_in_cells = ceil(repulsion_radius / cell_size)
	
	# Calculate bounds of cells to check
	var min_x = max(0, agent_grid_pos.x - radius_in_cells)
	var max_x = min(grid_width - 1, agent_grid_pos.x + radius_in_cells)
	var min_y = max(0, agent_grid_pos.y - radius_in_cells)
	var max_y = min(grid_height - 1, agent_grid_pos.y + radius_in_cells)
	
	# Update each cell within range
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell_pos = grid_to_world(Vector2i(x, y)) + Vector2(cell_size * 0.5, cell_size * 0.5)
			var repulsion = _calculate_repulsion(cell_pos, agent_pos)
			# Accumulate repulsion from this agent
			congestion_vectors[y][x] += repulsion

func _combine_flow_maps():
	# Combine static flow map with congestion map
	# Store previous flow vectors for smoothing
	for y in range(grid_height):
		for x in range(grid_width):
			previous_flow_vectors[y][x] = flow_vectors[y][x]
			
			# Combine static flow (goal + obstacles) with congestion (agent repulsion)
			var static_flow = static_flow_vectors[y][x]
			var congestion = congestion_vectors[y][x]
			
			# Blend: static flow provides base direction, congestion adds repulsion
			# If there's strong congestion, reduce static flow influence
			var effective_static_weight = goal_weight
			if congestion.length() > 1.0:
				effective_static_weight = goal_weight * 0.7  # Reduce static influence when congested
			
			var combined_flow = static_flow * effective_static_weight + congestion
			
			# Normalize
			if combined_flow.length() > 0.001:
				flow_vectors[y][x] = combined_flow.normalized()
			else:
				flow_vectors[y][x] = static_flow  # Fallback to static flow
			
			# Apply smoothing to final flow vectors
			if smoothing_factor > 0.0:
				var blend = 1.0 - smoothing_factor
				flow_vectors[y][x] = previous_flow_vectors[y][x].lerp(flow_vectors[y][x], blend)

# Old _calculate_flow_vector removed - functionality split into _calculate_static_flow_vector and _update_congestion_map

func _calculate_repulsion(cell_pos: Vector2, agent_pos: Vector2) -> Vector2:
	var to_cell = cell_pos - agent_pos
	var dist = to_cell.length()
	
	# Check if agent is within repulsion radius and above minimum distance
	if dist > repulsion_radius or dist < min_repulsion_distance:
		return Vector2.ZERO
	
	# Use smoother falloff function to avoid instabilities
	# Linear falloff from center to edge of repulsion radius
	var normalized_dist = (dist - min_repulsion_distance) / (repulsion_radius - min_repulsion_distance)
	normalized_dist = clamp(normalized_dist, 0.0, 1.0)
	var falloff = 1.0 - normalized_dist  # 1 at min_distance, 0 at repulsion_radius
	
	# Use linear falloff instead of inverse square to avoid extreme forces
	# This creates smoother, more stable flow
	var force = repulsion_strength * falloff * falloff
	
	# Normalize direction
	if dist > 0.001:
		return to_cell.normalized() * force
	else:
		return Vector2.ZERO

func _calculate_obstacle_repulsion(cell_pos: Vector2, obstacle: Dictionary) -> Vector2:
	# obstacle is {position: Vector2, size: Vector2}
	var obstacle_pos = obstacle["position"]
	var obstacle_size = obstacle["size"]
	
	# Calculate obstacle bounds
	var obstacle_min = obstacle_pos
	var obstacle_max = obstacle_pos + obstacle_size
	var obstacle_center = obstacle_pos + obstacle_size * 0.5
	
	# Check if cell is inside obstacle
	var inside_x = cell_pos.x >= obstacle_min.x and cell_pos.x <= obstacle_max.x
	var inside_y = cell_pos.y >= obstacle_min.y and cell_pos.y <= obstacle_max.y
	
	if inside_x and inside_y:
		# Cell is inside obstacle - push away from center
		var away_from_center = cell_pos - obstacle_center
		var dist = away_from_center.length()
		if dist < 0.001:
			# Exactly at center, push in a default direction
			away_from_center = Vector2(1.0, 0.0)
		return away_from_center.normalized() * obstacle_repulsion_strength * 2.0
	
	# Calculate closest point on obstacle rectangle to cell position
	var closest_point = Vector2(
		clamp(cell_pos.x, obstacle_min.x, obstacle_max.x),
		clamp(cell_pos.y, obstacle_min.y, obstacle_max.y)
	)
	
	# Calculate distance from cell to closest point on obstacle
	var to_cell = cell_pos - closest_point
	var dist = to_cell.length()
	
	# Check if cell is within obstacle repulsion radius
	if dist > obstacle_repulsion_radius or dist < min_repulsion_distance:
		return Vector2.ZERO
	
	# Use same falloff as agent repulsion, but stronger for obstacles
	var normalized_dist = (dist - min_repulsion_distance) / (obstacle_repulsion_radius - min_repulsion_distance)
	normalized_dist = clamp(normalized_dist, 0.0, 1.0)
	var falloff = 1.0 - normalized_dist
	
	# Determine which side of obstacle the cell is on
	# Check if cell is on top or bottom side (y is outside obstacle bounds, x is within extended bounds)
	var on_top = cell_pos.y < obstacle_min.y and cell_pos.x >= obstacle_min.x - obstacle_size.x * 0.2 and cell_pos.x <= obstacle_max.x + obstacle_size.x * 0.2
	var on_bottom = cell_pos.y > obstacle_max.y and cell_pos.x >= obstacle_min.x - obstacle_size.x * 0.2 and cell_pos.x <= obstacle_max.x + obstacle_size.x * 0.2
	var on_top_or_bottom = on_top or on_bottom
	
	# Check if cell is in front or behind
	var in_front = cell_pos.x < obstacle_min.x
	var behind = cell_pos.x > obstacle_max.x
	
	# Determine side multiplier
	var side_multiplier = 1.0
	if on_top_or_bottom:
		# On top or bottom side
		side_multiplier = top_bottom_repulsion_multiplier
	elif in_front:
		# In front (left side)
		side_multiplier = front_repulsion_multiplier
	elif behind:
		# Behind (right side)
		side_multiplier = back_repulsion_multiplier
	
	# If multiplier is zero or very small, return no repulsion
	if side_multiplier < 0.001:
		return Vector2.ZERO
	
	# Obstacle repulsion - use stronger falloff curve with side-based multiplier
	var base_force = obstacle_repulsion_strength * falloff * falloff * falloff  # Cubic falloff for stronger near obstacle
	var force = base_force * side_multiplier
	
	# Special handling for cells in front of obstacle (left side)
	# Only apply special "around" flow if not on top/bottom
	if in_front and not on_top_or_bottom:
		# Instead of repulsing left (which conflicts with goal direction),
		# create a flow that goes around the obstacle (up or down)
		var vertical_offset = cell_pos.y - obstacle_center.y
		var vertical_distance = abs(vertical_offset)
		
		# Determine which way to go around (prefer shorter path)
		var go_up = vertical_offset < 0  # Cell is above center, go up
		var go_down = vertical_offset > 0  # Cell is below center, go down
		
		# If cell is near center vertically, prefer going up (arbitrary choice)
		if abs(vertical_offset) < obstacle_size.y * 0.1:
			go_up = true
			go_down = false
		
		# Create flow vector that goes around: slightly right (toward goal) and up/down
		var around_flow = Vector2.ZERO
		if go_up:
			# Flow goes up and slightly right
			around_flow = Vector2(0.3, -1.0).normalized()
		else:
			# Flow goes down and slightly right
			around_flow = Vector2(0.3, 1.0).normalized()
		
		# Stronger flow when closer to obstacle center vertically
		# Front side already has front_repulsion_multiplier applied, so this adds extra strength near center
		var center_proximity = 1.0 - clamp(vertical_distance / (obstacle_size.y * 0.5), 0.0, 1.0)
		var adjusted_force = force * (1.0 + center_proximity * 1.5)  # Additional boost near center
		
		return around_flow * adjusted_force
	
	# For cells on other sides (top, bottom, back), use normal repulsion (away from obstacle)
	# Direction: from closest point on obstacle to cell (points away from obstacle)
	if dist > 0.001:
		var repulsion_dir = to_cell.normalized()
		return repulsion_dir * force
	else:
		# Very close to obstacle edge, push away from center
		var away_from_center = (cell_pos - obstacle_center)
		if away_from_center.length() > 0.001:
			return away_from_center.normalized() * obstacle_repulsion_strength * side_multiplier
		else:
			return Vector2.ZERO

func _build_spatial_grid(agent_positions: Array):
	# Build spatial hash grid for optimization
	for agent_pos in agent_positions:
		var bucket_key = _get_spatial_bucket_key(agent_pos)
		if not spatial_grid.has(bucket_key):
			spatial_grid[bucket_key] = []
		spatial_grid[bucket_key].append(agent_pos)

func _get_spatial_bucket_key(pos: Vector2) -> Vector2i:
	var bucket_x = int(pos.x / spatial_bucket_size)
	var bucket_y = int(pos.y / spatial_bucket_size)
	return Vector2i(bucket_x, bucket_y)

func _get_nearby_agents(cell_pos: Vector2, all_agents: Array) -> Array:
	# Get agents from spatial buckets near the cell
	var nearby: Array = []
	var cell_bucket = _get_spatial_bucket_key(cell_pos)
	
	# Check current bucket and 8 neighboring buckets
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var bucket_key = cell_bucket + Vector2i(dx, dy)
			if spatial_grid.has(bucket_key):
				nearby.append_array(spatial_grid[bucket_key])
	
	return nearby

func get_flow_vector(world_pos: Vector2) -> Vector2:
	# Clamp world position to valid range
	var clamped_pos = Vector2(
		clamp(world_pos.x, 0, world_size.x),
		clamp(world_pos.y, 0, world_size.y)
	)
	
	# Convert to grid coordinates
	var grid_pos = world_to_grid(clamped_pos)
	var cell_x = grid_pos.x
	var cell_y = grid_pos.y
	
	# Clamp to valid grid bounds
	cell_x = clamp(cell_x, 0, grid_width - 1)
	cell_y = clamp(cell_y, 0, grid_height - 1)
	
	# Get fractional part for interpolation
	var cell_world_pos = grid_to_world(Vector2i(cell_x, cell_y))
	var local_pos = clamped_pos - cell_world_pos
	var fx = local_pos.x / cell_size
	var fy = local_pos.y / cell_size
	
	# Clamp interpolation factors
	fx = clamp(fx, 0.0, 1.0)
	fy = clamp(fy, 0.0, 1.0)
	
	# Get four corner vectors
	var v00 = flow_vectors[cell_y][cell_x]
	var v10 = flow_vectors[cell_y][min(cell_x + 1, grid_width - 1)]
	var v01 = flow_vectors[min(cell_y + 1, grid_height - 1)][cell_x]
	var v11 = flow_vectors[min(cell_y + 1, grid_height - 1)][min(cell_x + 1, grid_width - 1)]
	
	# Bilinear interpolation
	var v0 = v00.lerp(v10, fx)
	var v1 = v01.lerp(v11, fx)
	var result = v0.lerp(v1, fy)
	
	# Normalize result
	if result.length() > 0.001:
		return result.normalized()
	else:
		return Vector2(1.0, 0.0)  # Default to right

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var grid_x = int(world_pos.x / cell_size)
	var grid_y = int(world_pos.y / cell_size)
	return Vector2i(grid_x, grid_y)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * cell_size, grid_pos.y * cell_size)

func _draw():
	if not show_visualization:
		return
	
	# Draw grid lines (optional)
	if show_grid_lines:
		for x in range(grid_width + 1):
			var x_pos = x * cell_size
			draw_line(Vector2(x_pos, 0), Vector2(x_pos, world_size.y), grid_line_color, 1.0)
		for y in range(grid_height + 1):
			var y_pos = y * cell_size
			draw_line(Vector2(0, y_pos), Vector2(world_size.x, y_pos), grid_line_color, 1.0)
	
	# Draw flow vectors as arrows
	# Note: This shows the flow vector at cell centers.
	# Nodes sample with bilinear interpolation, so they may see slightly different vectors.
	var arrow_length = cell_size * vector_scale
	var arrow_head_size = arrow_length * 0.3
	
	for y in range(grid_height):
		for x in range(grid_width):
			var cell_center = grid_to_world(Vector2i(x, y)) + Vector2(cell_size * 0.5, cell_size * 0.5)
			var flow_vec = flow_vectors[y][x]
			
			# Skip if vector is too small
			if flow_vec.length() < 0.01:
				continue
			
			# Calculate arrow end point
			var arrow_dir = flow_vec.normalized()
			var arrow_end = cell_center + arrow_dir * arrow_length
			
			# Draw arrow line
			draw_line(cell_center, arrow_end, vector_color, 2.0)
			
			# Draw arrow head
			var perp = Vector2(-arrow_dir.y, arrow_dir.x)
			var arrow_point1 = arrow_end - arrow_dir * arrow_head_size + perp * arrow_head_size * 0.5
			var arrow_point2 = arrow_end - arrow_dir * arrow_head_size - perp * arrow_head_size * 0.5
			draw_line(arrow_end, arrow_point1, vector_color, 2.0)
			draw_line(arrow_end, arrow_point2, vector_color, 2.0)

func _process(_delta):
	# Queue redraw every frame to update visualization
	if show_visualization:
		queue_redraw()
