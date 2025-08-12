extends Node2D

@onready var camera = $Camera
@onready var color_rect = $ColorRect

var camera_speed := 300.0
var camera_angle := 0.0

func _ready():
    set_process(true)
    update_shader()

func _process(delta):
    var input_vec = Vector2.ZERO
    if Input.is_action_pressed("ui_up"):
        input_vec.y -= 1
    if Input.is_action_pressed("ui_down"):
        input_vec.y += 1
    if Input.is_action_pressed("ui_left"):
        input_vec.x -= 1
    if Input.is_action_pressed("ui_right"):
        input_vec.x += 1
    if Input.is_action_pressed("move_forward"):
        camera.position += Vector2(cos(camera_angle), sin(camera_angle)) * camera_speed * delta
    if Input.is_action_pressed("move_backward"):
        camera.position -= Vector2(cos(camera_angle), sin(camera_angle)) * camera_speed * delta
    if Input.is_action_pressed("move_left"):
        camera_angle -= 1.5 * delta
    if Input.is_action_pressed("move_right"):
        camera_angle += 1.5 * delta
    camera.position += input_vec.normalized() * camera_speed * delta
    update_shader()

func update_shader():
    var mat = color_rect.material
    if mat:
        mat.set_shader_parameter("camera_pos", camera.position)
        mat.set_shader_parameter("camera_angle", camera_angle)
