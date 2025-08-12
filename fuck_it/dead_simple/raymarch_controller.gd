extends Control
class_name RayMarchController

@export var camera: Camera3D
@export var depth_viewer: Control  # This will be your %Depthviewer node

var shader_material: ShaderMaterial

func _ready():
    # Get references if not assigned
    if not camera:
        camera = get_viewport().get_camera_3d()
    if not depth_viewer:
        depth_viewer = get_node("%Depthviewer") if has_node("%Depthviewer") else null
    
    setup_shader_material()
    
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
