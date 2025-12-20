# Flow Map Implementation Plan - Dynamic Density-Based Approach

## What is a Flow Map?

A **Flow Map** is a grid-based data structure that stores directional vectors (flow vectors) at each grid cell. Agents sample the flow map at their current position to determine which direction they should move, creating natural crowd flow patterns.

### Key Concepts:
- **Grid-based**: The world is divided into a regular grid of cells
- **Vector Field**: Each cell contains a Vector2 representing desired movement direction
- **Dynamic**: Flow map recalculates every frame based on current agent positions
- **Density-based**: Flow vectors point away from crowded areas, creating natural flow
- **Pure Flow Map**: No separation forces needed - the flow map itself handles avoidance

## How Dynamic Flow Maps Work

1. **Grid Creation**: Divide the playable area into a grid
2. **Density Calculation**: For each cell, calculate density (how many agents are nearby)
3. **Flow Vector Calculation**: For each cell, calculate flow vector that:
   - Points toward the goal (right side of screen)
   - Points away from high-density areas
   - Creates natural flow around bottlenecks
4. **Recalculation**: Recalculate every frame based on current agent positions
5. **Sampling**: Agents query the flow map at their position to get steering direction

## Architecture: Pure Flow Map Approach

**Key Principle**: The flow map itself is the collision avoidance mechanism.

- **One shared flow map** for all agents
- **Recalculated every frame** based on all agent positions
- **No separation forces** - agents only use flow map direction
- Flow map naturally guides agents around crowded areas

## Flow Vector Calculation Algorithm

For each grid cell, calculate flow vector using this formula:

```
flow_vector = normalize(goal_direction + repulsion_sum)
```

Where:
- `goal_direction`: Vector pointing toward right side of screen (normalized)
- `repulsion_sum`: Sum of repulsion vectors from all nearby agents
- Final vector is normalized

### Detailed Algorithm:

For each grid cell at position `cell_pos`:

```gdscript
func calculate_flow_vector(cell_pos: Vector2, agent_positions: Array, goal: Vector2, repulsion_radius: float, repulsion_strength: float) -> Vector2:
    # 1. Goal direction (toward right side)
    var goal_dir = (goal - cell_pos).normalized()
    
    # 2. Calculate repulsion from all agents
    var repulsion = Vector2.ZERO
    for agent_pos in agent_positions:
        var to_cell = cell_pos - agent_pos
        var dist = to_cell.length()
        
        if dist < repulsion_radius and dist > 0.001:
            # Repulsion strength decreases with distance
            var strength = repulsion_strength / (dist * dist)
            repulsion += to_cell.normalized() * strength
    
    # 3. Blend goal direction with repulsion
    var flow = goal_dir + repulsion
    
    # 4. Normalize to get direction
    if flow.length() > 0.001:
        return flow.normalized()
    else:
        return goal_dir  # Fallback to goal direction
```

### Optimization: Spatial Hashing

Instead of checking all 120 agents for each cell, use spatial hashing:
- Divide space into buckets
- For each cell, only check agents in nearby buckets
- Reduces complexity from O(cells × agents) to O(cells × local_agents)

## Implementation Details

### Grid Cell Size Recommendation

For your use case (120 agents, dynamic recalculation):
- **Recommended: 32-48 pixels per cell**
- **Why**: 
  - Small enough for smooth flow
  - Large enough to keep computation manageable
  - With 1920x1080 screen: ~60×34 = 2040 cells
  - Each frame: 2040 cells × ~10-20 nearby agents = ~20k-40k calculations (doable)

**Performance consideration:**
- Smaller cells = smoother flow but more computation
- Larger cells = faster but less smooth
- 32-48px is a good balance

### Data Structure

**2D Array (Recommended)**
```gdscript
var flow_map: Array[Array] = []  # Array[Array[Vector2]]
# Access: flow_map[grid_y][grid_x]
```

**Additional structures for optimization:**
```gdscript
var density_map: Array[Array] = []  # Array[Array[float]] - optional, for visualization
var spatial_grid: Dictionary = {}   # For spatial hashing optimization
```

### Recalculation Strategy

**Every Frame Recalculation:**

```gdscript
func _physics_process(delta):
    # 1. Collect all agent positions
    var agent_positions = []
    for guy in guys.keys():
        if is_instance_valid(guy):
            agent_positions.append(guy.position)
    
    # 2. Recalculate flow map
    flow_map.recalculate(agent_positions, goal_position)
    
    # 3. Update agents using flow map
    for guy in guys.keys():
        var flow_dir = flow_map.get_flow_vector(guy.position)
        guy.velocity = flow_dir * speed
        guy.move_and_slide()
```

## Code Structure

```
FlowMap.gd
├── Properties
│   ├── cell_size: float (32-48)
│   ├── grid_width: int
│   ├── grid_height: int
│   ├── repulsion_radius: float (64-128) - how far agents affect flow
│   ├── repulsion_strength: float (1.0-5.0) - strength of repulsion
│   ├── goal_blend_weight: float (0.5-1.0) - how much to favor goal vs repulsion
│   └── flow_vectors: Array[Array[Vector2]]
├── Methods
│   ├── initialize(world_size: Vector2, cell_size: float)
│   ├── recalculate(agent_positions: Array, goal: Vector2)
│   ├── get_flow_vector(world_pos: Vector2) -> Vector2
│   ├── world_to_grid(world_pos: Vector2) -> Vector2i
│   └── grid_to_world(grid_pos: Vector2i) -> Vector2
```

## Flow Vector Calculation Details

### Repulsion Function

The repulsion from each agent should:
- Be strongest when agent is very close to cell
- Decrease with distance (inverse square law works well)
- Have a maximum radius (agents beyond this don't affect the cell)

```gdscript
func calculate_repulsion(cell_pos: Vector2, agent_pos: Vector2, radius: float, strength: float) -> Vector2:
    var to_cell = cell_pos - agent_pos
    var dist = to_cell.length()
    
    if dist > radius or dist < 0.001:
        return Vector2.ZERO
    
    # Inverse square law with falloff
    var normalized_dist = dist / radius  # 0 to 1
    var falloff = 1.0 - normalized_dist  # 1 at center, 0 at edge
    var force = strength * falloff * falloff / (dist * dist + 0.1)  # +0.1 to avoid division by zero
    
    return to_cell.normalized() * force
```

### Goal Direction

For your use case (moving left to right):
- Goal is right side of screen
- Each cell's goal direction points toward right edge
- Can use same y-coordinate or center of right edge

```gdscript
func get_goal_direction(cell_pos: Vector2, screen_width: float) -> Vector2:
    var goal = Vector2(screen_width, cell_pos.y)  # Point to right edge at same height
    return (goal - cell_pos).normalized()
```

### Blending Goal and Repulsion

```gdscript
var goal_dir = get_goal_direction(cell_pos, screen_width)
var repulsion = calculate_total_repulsion(cell_pos, agent_positions)

# Blend: goal direction + repulsion
var flow = goal_dir * goal_weight + repulsion
return flow.normalized()
```

## Sampling with Bilinear Interpolation

When an agent samples the flow map, use bilinear interpolation for smooth movement:

```gdscript
func get_flow_vector(world_pos: Vector2) -> Vector2:
    var grid_pos = world_to_grid(world_pos)
    var cell_x = grid_pos.x
    var cell_y = grid_pos.y
    
    # Get fractional part for interpolation
    var local_pos = world_pos - grid_to_world(grid_pos)
    var fx = local_pos.x / cell_size
    var fy = local_pos.y / cell_size
    
    # Get four corner vectors
    var v00 = flow_vectors[cell_y][cell_x]
    var v10 = flow_vectors[cell_y][cell_x + 1] if cell_x + 1 < grid_width else v00
    var v01 = flow_vectors[cell_y + 1][cell_x] if cell_y + 1 < grid_height else v00
    var v11 = flow_vectors[cell_y + 1][cell_x + 1] if (cell_x + 1 < grid_width and cell_y + 1 < grid_height) else v00
    
    # Bilinear interpolation
    var v0 = v00.lerp(v10, fx)
    var v1 = v01.lerp(v11, fx)
    return v0.lerp(v1, fy).normalized()
```

## Performance Optimization

### 1. Spatial Hashing
- Divide grid into spatial buckets
- Only check agents in nearby buckets for each cell
- Reduces O(cells × agents) to O(cells × local_agents)

### 2. Early Exit
- If repulsion is very small, skip normalization
- Use approximate distance checks first

### 3. Multi-threading (Future)
- Could parallelize cell calculations
- Godot 4 supports worker threads

### 4. Update Frequency (Optional)
- Could update every 2-3 frames instead of every frame
- Still looks smooth but reduces computation

## Integration with flow_map_demo.gd

```gdscript
extends Node2D

@export var guy_count: int = 120
@export var guy_scene: PackedScene = preload("res://guy.tscn")
@export var flow_map_cell_size: float = 32.0
@export var repulsion_radius: float = 64.0
@export var repulsion_strength: float = 2.0

var guys: Dictionary = {}
var flow_map: FlowMap

func _ready():
    var viewport = get_viewport()
    var window_size = viewport.get_visible_rect().size
    
    # Initialize flow map
    flow_map = FlowMap.new()
    flow_map.initialize(window_size, flow_map_cell_size)
    flow_map.repulsion_radius = repulsion_radius
    flow_map.repulsion_strength = repulsion_strength
    add_child(flow_map)
    
    spawn_all_guys()

func _physics_process(_delta):
    var viewport = get_viewport()
    var window_size = viewport.get_visible_rect().size
    
    # Collect agent positions
    var agent_positions = []
    for guy in guys.keys():
        if is_instance_valid(guy):
            agent_positions.append(guy.position)
    
    # Recalculate flow map every frame
    var goal = Vector2(window_size.x, window_size.y * 0.5)  # Right side, center
    flow_map.recalculate(agent_positions, goal)
    
    # Update all guys using flow map
    var guys_to_remove = []
    
    for guy in guys.keys():
        if not is_instance_valid(guy):
            guys_to_remove.append(guy)
            continue
        
        var guy_data = guys[guy]
        var speed = guy_data["speed"]
        var target_position = guy_data["target"]
        
        # Get flow direction from flow map (pure flow map, no direct seek)
        var flow_direction = flow_map.get_flow_vector(guy.position)
        
        # Set velocity based on flow map
        guy.velocity = flow_direction * speed
        guy.move_and_slide()
        
        # Check if reached target
        var distance_to_target = guy.position.distance_to(target_position)
        if guy.position.x >= target_position.x or distance_to_target < 10.0:
            guys_to_remove.append(guy)
    
    # Remove and respawn
    for guy in guys_to_remove:
        if is_instance_valid(guy):
            guy.queue_free()
        guys.erase(guy)
        spawn_guy(window_size)
```

## Benefits of This Approach

1. **Pure Flow Map**: No separation forces needed
2. **Natural Crowd Flow**: Creates lanes and flow patterns automatically
3. **Dynamic**: Adapts to current crowd density
4. **Scalable**: Works with any number of agents
5. **Smooth**: Bilinear interpolation creates smooth movement

## Next Steps

1. Implement FlowMap class with dynamic recalculation
2. Integrate with flow_map_demo.gd
3. Test with 120 agents
4. Tune repulsion_radius and repulsion_strength
5. Add spatial hashing for optimization if needed
