extends Control
class_name RayMarchController

@export var camera: Camera3D
@export var depth_viewer: Control  # This will be your %Depthviewer node
@export var target_mesh: MeshInstance3D  # Any mesh you want to X-ray

var shader_material: ShaderMaterial
var vertex_texture: ImageTexture
var grid_texture: ImageTexture
var grid_resolution: int = 64  # Reduced resolution for faster preprocessing

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
    
    # Calculate mesh bounds for spatial grid
    var mesh_bounds = calculate_mesh_bounds(vertices)
    print("Mesh bounds: ", mesh_bounds[0], " to ", mesh_bounds[1])
    print("Mesh size: ", mesh_bounds[1] - mesh_bounds[0])
    
    # Remove triangle limit - we'll use spatial acceleration instead
    print("Processing all ", triangle_count, " triangles with spatial acceleration")
    
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
    
    print("Building spatial acceleration grid...")
    print("Mesh bounds: ", min_bound, " to ", max_bound)
    print("Grid size: ", grid_size)
    print("Triangle count: ", triangle_count)
    print("Grid resolution: ", grid_resolution, "^3")
    
    # Create spatial grid that stores triangle indices per cell
    var triangle_grid = {}  # Dictionary of Vector3i -> Array of triangle indices
    var max_triangles_per_cell = 0
    
    # For each triangle, find which grid cells it intersects
    for i in range(triangle_count):
        var tri_base = i * 3
        var v0 = vertices[indices[tri_base]]
        var v1 = vertices[indices[tri_base + 1]]
        var v2 = vertices[indices[tri_base + 2]]
        
        # Find triangle bounding box
        var tri_min = Vector3(
            min(v0.x, min(v1.x, v2.x)),
            min(v0.y, min(v1.y, v2.y)),
            min(v0.z, min(v1.z, v2.z))
        )
        var tri_max = Vector3(
            max(v0.x, max(v1.x, v2.x)),
            max(v0.y, max(v1.y, v2.y)),
            max(v0.z, max(v1.z, v2.z))
        )
        
        # Convert to grid coordinates
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
        cell_min = Vector3i(
            max(0, cell_min.x), max(0, cell_min.y), max(0, cell_min.z)
        )
        cell_max = Vector3i(
            min(grid_resolution-1, cell_max.x), 
            min(grid_resolution-1, cell_max.y), 
            min(grid_resolution-1, cell_max.z)
        )
        
        # Add triangle to all intersected cells
        for x in range(cell_min.x, cell_max.x + 1):
            for y in range(cell_min.y, cell_max.y + 1):
                for z in range(cell_min.z, cell_max.z + 1):
                    var cell_key = Vector3i(x, y, z)
                    if not triangle_grid.has(cell_key):
                        triangle_grid[cell_key] = []
                    triangle_grid[cell_key].append(i)
                    max_triangles_per_cell = max(max_triangles_per_cell, triangle_grid[cell_key].size())
    
    # Create a texture to store triangle indices per cell
    # Each cell gets multiple pixels to store triangle IDs
    var triangles_per_cell = min(max_triangles_per_cell, 32)  # Cap at 32 triangles per cell
    var grid_texture_width = grid_resolution
    var grid_texture_height = grid_resolution * grid_resolution * triangles_per_cell
    
    var grid_image = Image.create(grid_texture_width, grid_texture_height, false, Image.FORMAT_RF)
    
    # Fill the grid texture with triangle indices
    for cell_pos in triangle_grid:
        var triangle_list = triangle_grid[cell_pos]
        var x = cell_pos.x
        var base_y = (cell_pos.y * grid_resolution + cell_pos.z) * triangles_per_cell
        
        for i in range(min(triangle_list.size(), triangles_per_cell)):
            var pixel_y = base_y + i
            if pixel_y < grid_texture_height:
                grid_image.set_pixel(x, pixel_y, Color(float(triangle_list[i]), 0, 0, 1))
        
        # Mark end of list with -1
        if triangle_list.size() < triangles_per_cell:
            var end_marker_y = base_y + triangle_list.size()
            if end_marker_y < grid_texture_height:
                grid_image.set_pixel(x, end_marker_y, Color(-1.0, 0, 0, 1))
    
    # Create and pass grid texture to shader
    grid_texture = ImageTexture.new()
    grid_texture.set_image(grid_image)
    
    shader_material.set_shader_parameter("grid_texture", grid_texture)
    shader_material.set_shader_parameter("grid_resolution", grid_resolution)
    shader_material.set_shader_parameter("grid_min_bound", min_bound)
    shader_material.set_shader_parameter("grid_max_bound", max_bound)
    shader_material.set_shader_parameter("triangles_per_cell", triangles_per_cell)
    
    var cells_with_triangles = triangle_grid.size()
    var total_cells = grid_resolution * grid_resolution * grid_resolution
    print("Spatial grid created:")
    print("  Cells with triangles: ", cells_with_triangles, "/", total_cells)
    print("  Max triangles per cell: ", max_triangles_per_cell)
    print("  Triangles per cell (capped): ", triangles_per_cell)
    print("  Grid texture size: ", grid_texture_width, "x", grid_texture_height)
