shader_type canvas_item;

uniform vec2 camera_pos;
uniform float camera_angle;

// SDF for a sphere at (0,0) with radius 100
float sphere_sdf(vec2 p) {
    return length(p - vec2(0.0, 0.0)) - 100.0;
}

void fragment() {
    // Map screen UV to world coordinates
    vec2 uv = (UV - 0.5) * 2.0 * 400.0; // 800x800 world units

    // Camera ray direction
    float angle = camera_angle;
    vec2 cam_dir = vec2(cos(angle), sin(angle));

    // Raymarch from camera
    vec2 ray_origin = camera_pos;
    vec2 ray_dir = normalize(uv - camera_pos);
    float t = 0.0;
    float hit = 0.0;
    for (int i = 0; i < 64; i++) {
        vec2 p = ray_origin + ray_dir * t;
        float d = sphere_sdf(p);
        if (d < 0.5) {
            hit = 1.0;
            break;
        }
        t += d;
        if (t > 800.0) break;
    }
    if (hit > 0.5) {
        COLOR = vec4(1.0, 1.0, 1.0, 1.0);
    } else {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    }
}
