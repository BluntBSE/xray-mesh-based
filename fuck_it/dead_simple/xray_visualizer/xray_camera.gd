extends Camera3D
class_name XrayCamera

@export var movement_speed: float = 5.0
@export var rotation_speed: float = 2.0
@export var zoom_speed: float = 2.0
@export var target_focus: Vector3 = Vector3.ZERO

var is_rotating: bool = false
var last_mouse_position: Vector2
var distance_to_target: float = 5.0

func _ready():
    # Position camera to get a good initial view of the skeleton
    position = Vector3(0, 2, 5)
    look_at(target_focus, Vector3.UP)
    distance_to_target = position.distance_to(target_focus)

func _input(event):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            is_rotating = event.pressed
            if event.pressed:
                last_mouse_position = event.position
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
            zoom_in()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            zoom_out()
    
    elif event is InputEventMouseMotion and is_rotating:
        var delta = event.position - last_mouse_position
        orbit_around_target(delta)
        last_mouse_position = event.position

func _process(delta):
    handle_keyboard_input(delta)

func handle_keyboard_input(delta):
    var input_vector = Vector3()
    
    # Movement controls using direct key press checking
    if Input.is_key_pressed(KEY_W):
        input_vector -= transform.basis.z
    if Input.is_key_pressed(KEY_S):
        input_vector += transform.basis.z
    if Input.is_key_pressed(KEY_A):
        input_vector -= transform.basis.x
    if Input.is_key_pressed(KEY_D):
        input_vector += transform.basis.x
    if Input.is_key_pressed(KEY_Q):
        input_vector += transform.basis.y
    if Input.is_key_pressed(KEY_E):
        input_vector -= transform.basis.y
    
    # Apply movement
    if input_vector.length() > 0:
        input_vector = input_vector.normalized()
        position += input_vector * movement_speed * delta
        distance_to_target = position.distance_to(target_focus)

func orbit_around_target(mouse_delta: Vector2):
    var horizontal_angle = -mouse_delta.x * rotation_speed * 0.01
    var vertical_angle = -mouse_delta.y * rotation_speed * 0.01
    
    # Get current position relative to target
    var offset = position - target_focus
    
    # Horizontal rotation (around Y axis)
    var horizontal_rotation = Transform3D()
    horizontal_rotation = horizontal_rotation.rotated(Vector3.UP, horizontal_angle)
    offset = horizontal_rotation * offset
    
    # Vertical rotation (around local X axis)
    var right = offset.cross(Vector3.UP).normalized()
    var vertical_rotation = Transform3D()
    vertical_rotation = vertical_rotation.rotated(right, vertical_angle)
    offset = vertical_rotation * offset
    
    # Clamp vertical angle to prevent flipping
    var up_dot = offset.normalized().dot(Vector3.UP)
    if up_dot > 0.95 or up_dot < -0.95:
        # Skip this rotation if it would flip the camera
        return
    
    # Update position and look at target
    position = target_focus + offset
    look_at(target_focus, Vector3.UP)

func zoom_in():
    distance_to_target = max(0.5, distance_to_target - zoom_speed * 0.1)
    update_zoom()

func zoom_out():
    distance_to_target = min(20.0, distance_to_target + zoom_speed * 0.1)
    update_zoom()

func update_zoom():
    var direction = (position - target_focus).normalized()
    position = target_focus + direction * distance_to_target

func focus_on_skeleton(skeleton_bounds_min: Vector3, skeleton_bounds_max: Vector3):
    # Calculate optimal camera position for the skeleton
    target_focus = (skeleton_bounds_min + skeleton_bounds_max) * 0.5
    var bounds_size = skeleton_bounds_max - skeleton_bounds_min
    distance_to_target = bounds_size.length() * 1.5
    
    # Position camera at a good angle
    var camera_offset = Vector3(1, 1, 1).normalized() * distance_to_target
    position = target_focus + camera_offset
    look_at(target_focus, Vector3.UP)
