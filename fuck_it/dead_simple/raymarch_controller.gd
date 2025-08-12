extends Control
class_name RayMarchController

@export var camera: Camera3D
@export var depth_viewer: Control  # This will be your %Depthviewer node
@export var target_mesh: MeshInstance3D  # Any mesh you want to X-ray

var shader_material: ShaderMaterial
var vertex_texture: ImageTexture
var grid_texture: ImageTexture
var grid_resolution: int = 128  # Much higher resolution: 128x128x128 grid cells

func _ready():
    # Get references if not assigned
    if not camera:
        camera = get_viewport().get_camera_3d()
    if not depth_viewer:
        depth_viewer = get_node("%Depthviewer") if has_node("%Depthviewer") else null
    # target_mesh must be assigned via the inspector - no fallback to %MyPrism
    
    setup_shader_material()
    extract_mesh_data()
    
func setup_shader_material():
    # Load our ray marching shader
    var shader = load("res://fuck_it/dead_simple/raymarch_hit_detector.gdshader")
    shader_material = ShaderMaterial.new()
    shader_material.shader = shader
    
    # Apply to depth viewer (ColorRect should work)
    if depth_viewer and depth_viewer is ColorRect:
        depth_viewer.material = shader_material
        print("Shader material applied to Depthviewer")
    else:
        print("Warning: depth_viewer not found or not a ColorRect")

func _process(_delta):
    update_shader_uniforms()

func update_shader_uniforms():
    if not shader_material or not camera:
        return
        
    # Pass camera data to shader
    shader_material.set_shader_parameter("camera_transform", camera.global_transform)
    shader_material.set_shader_parameter("camera_projection", camera.get_camera_projection())
    shader_material.set_shader_parameter("screen_size", get_viewport().get_visible_rect().size)
    
    # Pass mesh transform to shader
    if target_mesh:
        shader_material.set_shader_parameter("mesh_transform", target_mesh.global_transform)

func extract_mesh_data():
    if not target_mesh or not target_mesh.mesh:
        print("Error: No target mesh found!")
        return
    
    var mesh = target_mesh.mesh
    var arrays = mesh.surface_get_arrays(0)
    var vertices = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
    var indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
    
    var triangle_count = indices.size() / 3
    print("Mesh has ", vertices.size(), " vertices and ", triangle_count, " triangles")
    
    # Remove triangle limit - we'll use spatial acceleration instead
    print("Processing all ", triangle_count, " triangles with spatial acceleration")
    
    # Calculate mesh bounds for spatial grid
    var mesh_bounds = calculate_mesh_bounds(vertices)
    
    # Create vertex texture and spatial grid
    create_vertex_texture(vertices, indices, triangle_count)
    create_spatial_grid(vertices, indices, triangle_count, mesh_bounds)

func calculate_mesh_bounds(vertices: PackedVector3Array) -> Array:
    var min_bound = Vector3(INF, INF, INF)
    var max_bound = Vector3(-INF, -INF, -INF)
    
    for vertex in vertices:
        min_bound = Vector3(min(min_bound.x, vertex.x), min(min_bound.y, vertex.y), min(min_bound.z, vertex.z))
        max_bound = Vector3(max(max_bound.x, vertex.x), max(max_bound.y, vertex.y), max(max_bound.z, vertex.z))
    
    # Add small padding
    var padding = (max_bound - min_bound) * 0.1
    min_bound -= padding
    max_bound += padding
    
    return [min_bound, max_bound]

func create_vertex_texture(vertices: PackedVector3Array, indices: PackedInt32Array, triangle_count: int):
    # Create vertex texture - pack triangle vertices (3 vertices per triangle)
    var texture_width = min(triangle_count * 3, 4096)  # Max texture width
    var texture_height = max(1, (triangle_count * 3 + texture_width - 1) / texture_width)
    
    var image = Image.create(texture_width, texture_height, false, Image.FORMAT_RGBF)
    
    # Pack triangle vertices into the texture
    for i in range(triangle_count):
        var tri_base = i * 3
        for j in range(3):
            var vertex_idx = indices[tri_base + j]
            var vertex = vertices[vertex_idx]
            
            var pixel_idx = tri_base + j
            var x = pixel_idx % texture_width
            var y = pixel_idx / texture_width
            
            image.set_pixel(x, y, Color(vertex.x, vertex.y, vertex.z))
    
    # Create texture and pass to shader
    vertex_texture = ImageTexture.new()
    vertex_texture.set_image(image)
    
    shader_material.set_shader_parameter("vertex_texture", vertex_texture)
    shader_material.set_shader_parameter("triangle_count", triangle_count)
    shader_material.set_shader_parameter("texture_width", texture_width)

func create_spatial_grid(vertices: PackedVector3Array, indices: PackedInt32Array, triangle_count: int, bounds: Array):
    var min_bound = bounds[0] as Vector3
    var max_bound = bounds[1] as Vector3
    var grid_size = max_bound - min_bound
    
    # Create a simple grid texture: each cell stores triangle IDs
    # For now, we'll use a simpler approach: store triangle density per cell
    var grid_image = Image.create(grid_resolution, grid_resolution * grid_resolution, false, Image.FORMAT_RF)
    
    # Count triangles per grid cell
    var triangle_counts = {}
    
    for i in range(triangle_count):
        var tri_base = i * 3
        # Get triangle vertices
        var v0 = vertices[indices[tri_base]]
        var v1 = vertices[indices[tri_base + 1]]
        var v2 = vertices[indices[tri_base + 2]]
        
        # Find triangle bounding box
        var tri_min = Vector3(min(v0.x, min(v1.x, v2.x)), min(v0.y, min(v1.y, v2.y)), min(v0.z, min(v1.z, v2.z)))
        var tri_max = Vector3(max(v0.x, max(v1.x, v2.x)), max(v0.y, max(v1.y, v2.y)), max(v0.z, max(v1.z, v2.z)))
        
        # Find affected grid cells
        var cell_min = Vector3i(
            int((tri_min.x - min_bound.x) / grid_size.x * grid_resolution),
            int((tri_min.y - min_bound.y) / grid_size.y * grid_resolution),
            int((tri_min.z - min_bound.z) / grid_size.z * grid_resolution)
        )
        var cell_max = Vector3i(
            int((tri_max.x - min_bound.x) / grid_size.x * grid_resolution),
            int((tri_max.y - min_bound.y) / grid_size.y * grid_resolution),
            int((tri_max.z - min_bound.z) / grid_size.z * grid_resolution)
        )
        
        # Clamp to grid bounds
        cell_min = Vector3i(max(0, cell_min.x), max(0, cell_min.y), max(0, cell_min.z))
        cell_max = Vector3i(min(grid_resolution-1, cell_max.x), min(grid_resolution-1, cell_max.y), min(grid_resolution-1, cell_max.z))
        
        # Add triangle to affected cells
        for x in range(cell_min.x, cell_max.x + 1):
            for y in range(cell_min.y, cell_max.y + 1):
                for z in range(cell_min.z, cell_max.z + 1):
                    var cell_key = Vector3i(x, y, z)
                    if not triangle_counts.has(cell_key):
                        triangle_counts[cell_key] = []
                    triangle_counts[cell_key].append(i)
    
    # Store grid data (simplified: just triangle density for now)
    for cell_pos in triangle_counts:
        var x = cell_pos.x
        var y = cell_pos.y * grid_resolution + cell_pos.z  # Flatten 3D to 2D
        if y < grid_resolution * grid_resolution:
            var density = min(1.0, float(triangle_counts[cell_pos].size()) / 20.0)  # Higher normalization for smoother gradients
            grid_image.set_pixel(x, y, Color(density, 0, 0))
    
    # Create grid texture
    grid_texture = ImageTexture.new()
    grid_texture.set_image(grid_image)
    
    # Pass grid data to shader
    shader_material.set_shader_parameter("grid_texture", grid_texture)
    shader_material.set_shader_parameter("grid_resolution", grid_resolution)
    shader_material.set_shader_parameter("grid_min_bound", min_bound)
    shader_material.set_shader_parameter("grid_max_bound", max_bound)
    
    print("Created spatial grid: ", grid_resolution, "^3 cells, max triangles per cell: ", 
          triangle_counts.values().map(func(arr): return arr.size()).max() if triangle_counts.size() > 0 else 0)
