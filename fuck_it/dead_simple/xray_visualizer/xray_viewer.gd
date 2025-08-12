extends ColorRect
class_name XrayViewer

@export var target_mesh: MeshInstance3D
@export var camera: Camera3D
@export var use_analytical_method: bool = true  # Use simple analytical shapes vs depth method

var shader_material: ShaderMaterial
var depth_renderer: SubViewport
var depth_camera: Camera3D

func _ready():
    setup_shader()
    setup_depth_rendering()
    
    # Get references from scene
    var scene_root = get_tree().current_scene
    if scene_root:
        camera = scene_root.get_node("XrayCamera") if scene_root.has_node("XrayCamera") else null
        target_mesh = scene_root.get_node("SkeletonMesh") if scene_root.has_node("SkeletonMesh") else null
    
    if target_mesh and target_mesh.mesh:
        process_mesh()
    
    print("X-ray visualizer ready!")

func setup_shader():
    var shader = preload("res://fuck_it/dead_simple/xray_visualizer/xray_shader.gdshader")
    shader_material = ShaderMaterial.new()
    shader_material.shader = shader
    
    # Set default parameters for good X-ray visualization
    shader_material.set_shader_parameter("material_density", 1.2)
    shader_material.set_shader_parameter("step_size", 0.05)
    shader_material.set_shader_parameter("max_steps", 200)
    shader_material.set_shader_parameter("max_distance", 5.0)
    shader_material.set_shader_parameter("use_depth_method", not use_analytical_method)
    
    # Apply to this ColorRect
    self.material = shader_material

func setup_depth_rendering():
    # Create a SubViewport for depth rendering (if using depth method)
    if not use_analytical_method:
        depth_renderer = SubViewport.new()
        depth_renderer.size = Vector2i(512, 512)  # Reasonable resolution for depth
        depth_renderer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        
        depth_camera = Camera3D.new()
        depth_renderer.add_child(depth_camera)
        add_child(depth_renderer)
        
        print("Depth rendering setup complete")

func process_mesh():
    print("Processing mesh for X-ray visualization...")
    
    if not target_mesh or not target_mesh.mesh:
        print("Error: No valid mesh found")
        return
    
    var mesh = target_mesh.mesh
    var triangle_count = 0
    
    # Calculate triangle count for info
    if mesh.get_surface_count() > 0:
        var arrays = mesh.surface_get_arrays(0)
        var indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
        if indices:
            triangle_count = indices.size() / 3
    
    print("Mesh info: ", triangle_count, " triangles")
    
    # Calculate mesh bounds for camera positioning
    var aabb = mesh.get_aabb()
    var world_aabb = target_mesh.global_transform * aabb
    
    print("Mesh bounds: ", world_aabb.position, " to ", world_aabb.position + world_aabb.size)
    
    # Setup camera focus if available
    if camera and camera.has_method("focus_on_skeleton"):
        camera.focus_on_skeleton(world_aabb.position, world_aabb.position + world_aabb.size)
    
    print("X-ray preprocessing complete!")

func _process(_delta):
    if shader_material and camera:
        # Update shader uniforms every frame
        shader_material.set_shader_parameter("camera_transform", camera.global_transform)
        shader_material.set_shader_parameter("camera_projection", camera.get_camera_projection())
        shader_material.set_shader_parameter("screen_size", get_viewport().get_visible_rect().size)
        
        if target_mesh:
            shader_material.set_shader_parameter("mesh_transform", target_mesh.global_transform)
        
        # Update depth rendering if using depth method
        if not use_analytical_method and depth_camera and camera:
            depth_camera.global_transform = camera.global_transform
            depth_camera.fov = camera.fov
            depth_camera.near = camera.near
            depth_camera.far = camera.far
            
            # Pass depth texture to shader
            var depth_texture = depth_renderer.get_texture()
            if depth_texture:
                shader_material.set_shader_parameter("mesh_depth_texture", depth_texture)

# Helper function to switch between methods
func set_rendering_method(analytical: bool):
    use_analytical_method = analytical
    if shader_material:
        shader_material.set_shader_parameter("use_depth_method", not use_analytical_method)
    
    if use_analytical_method:
        print("Switched to analytical method (simple shapes)")
    else:
        print("Switched to depth buffer method (complex meshes)")

# Expose controls for tweaking
func set_material_density(density: float):
    if shader_material:
        shader_material.set_shader_parameter("material_density", density)

func set_step_size(size: float):
    if shader_material:
        shader_material.set_shader_parameter("step_size", size)

func set_max_steps(steps: int):
    if shader_material:
        shader_material.set_shader_parameter("max_steps", steps)
