extends Camera3D
class_name RayMarchCamera1

@export var movement_speed: float = 5.0
@export var mouse_sensitivity: float = 0.002
@export var zoom_speed: float = 2.0

var is_rotating: bool = false

func _ready():
    # Set initial position - NO look_at calls!
    position = Vector3(0, 0, 8)

func _input(event):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            is_rotating = event.pressed
            if is_rotating:
                Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
            else:
                Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
            move_closer()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            move_away()
    
    elif event is InputEventMouseMotion and is_rotating:
        # Simple free-look rotation - no orbit, no snapping!
        # Horizontal rotation (yaw) around Y axis
        rotate_y(-event.relative.x * mouse_sensitivity)
        
        # Vertical rotation (pitch) around local X axis
        rotate_object_local(Vector3(1, 0, 0), -event.relative.y * mouse_sensitivity)

func _process(delta):
    handle_keyboard_input(delta)

func handle_keyboard_input(delta):
    var input_vector = Vector3.ZERO
    
    # Calculate FOV scale factor (normalize around 75 degrees)
    var fov_scale = fov / 75.0
    
    # A and D movement (left/right) - no FOV scaling
    if Input.is_key_pressed(KEY_D):
        input_vector.x += 1
    if Input.is_key_pressed(KEY_A):
        input_vector.x -= 1
    
    # W and S movement (forward/backward) - scaled by FOV
    if Input.is_key_pressed(KEY_S):
        input_vector.z += fov_scale
    if Input.is_key_pressed(KEY_W):
        input_vector.z -= fov_scale
    
    # Q and E movement (up/down) - check if this feels right
    if Input.is_key_pressed(KEY_E):
        input_vector.y += 1  # E moves up
    if Input.is_key_pressed(KEY_Q):
        input_vector.y -= 1  # Q moves down
    
    if input_vector != Vector3.ZERO:
        input_vector = input_vector.normalized()
        var movement = transform.basis * input_vector * movement_speed * delta
        position += movement

func move_closer():
    # Move in the direction the camera is facing (forward)
    var forward = -transform.basis.z.normalized()
    position += forward * zoom_speed * 0.1

func move_away():
    # Move opposite to the direction the camera is facing (backward)
    var backward = transform.basis.z.normalized()
    position += backward * zoom_speed * 0.1
