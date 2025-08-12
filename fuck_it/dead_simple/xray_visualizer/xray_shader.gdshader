shader_type canvas_item;

// Camera uniforms
uniform mat4 camera_transform;
uniform mat4 camera_projection;
uniform vec2 screen_size;

// Mesh data uniforms
uniform sampler2D mesh_depth_texture : filter_linear;
uniform sampler2D mesh_normal_texture : filter_linear;
uniform mat4 mesh_transform;
uniform bool use_depth_method = true;

// Simplified volumetric parameters
uniform float material_density : hint_range(0.1, 3.0) = 1.0;
uniform float step_size : hint_range(0.01, 0.2) = 0.05;
uniform int max_steps : hint_range(50, 500) = 200;
uniform float max_distance : hint_range(1.0, 10.0) = 5.0;

varying vec2 screen_uv;

void vertex() {
    screen_uv = UV;
}

// Simple depth-based inside/outside approximation
float get_mesh_thickness_at_ray(vec3 ray_origin, vec3 ray_direction, float max_dist) {
    float total_thickness = 0.0;
    float current_distance = 0.0;
    bool inside_mesh = false;
    
    // March along the ray
    for (int i = 0; i < max_steps; i++) {
        vec3 current_pos = ray_origin + ray_direction * current_distance;
        
        // Project to screen space to sample depth
        vec4 clip_pos = camera_projection * inverse(camera_transform) * vec4(current_pos, 1.0);
        if (clip_pos.w <= 0.0) {
            current_distance += step_size;
            if (current_distance > max_dist) break;
            continue;
        }
        
        vec3 ndc = clip_pos.xyz / clip_pos.w;
        vec2 screen_coord = ndc.xy * 0.5 + 0.5;
        
        // Check if we're within screen bounds
        if (any(lessThan(screen_coord, vec2(0.0))) || any(greaterThan(screen_coord, vec2(1.0)))) {
            current_distance += step_size;
            if (current_distance > max_dist) break;
            continue;
        }
        
        // Sample mesh depth
        float mesh_depth = texture(mesh_depth_texture, screen_coord).r;
        float current_depth = (ndc.z + 1.0) * 0.5; // Convert to 0-1 range
        
        // Simple inside/outside logic based on depth comparison
        bool was_inside = inside_mesh;
        inside_mesh = current_depth > mesh_depth;
        
        // If we just entered or are inside, accumulate thickness
        if (inside_mesh || (was_inside && !inside_mesh)) {
            total_thickness += step_size;
        }
        
        current_distance += step_size;
        if (current_distance > max_dist) break;
    }
    
    return total_thickness;
}

// Simplified volumetric rendering using analytical shapes
float get_analytical_density(vec3 ray_origin, vec3 ray_direction) {
    // For simple shapes like sphere/cube, use analytical inside/outside testing
    vec3 mesh_center = mesh_transform[3].xyz;
    
    // Extract approximate scale from transform matrix
    vec3 scale = vec3(
        length(mesh_transform[0].xyz),
        length(mesh_transform[1].xyz),
        length(mesh_transform[2].xyz)
    );
    float avg_scale = (scale.x + scale.y + scale.z) / 3.0;
    
    float total_density = 0.0;
    float current_distance = 0.0;
    
    // Ray march with analytical sphere/box testing
    for (int i = 0; i < max_steps; i++) {
        vec3 current_pos = ray_origin + ray_direction * current_distance;
        
        // Distance to mesh center
        float dist_to_center = distance(current_pos, mesh_center);
        
        // Simple sphere approximation (works well for most convex shapes)
        bool inside_shape = dist_to_center < (avg_scale * 0.5);
        
        if (inside_shape) {
            // Add density with falloff towards center (more realistic for X-ray)
            float depth_factor = 1.0 - (dist_to_center / (avg_scale * 0.5));
            total_density += material_density * step_size * depth_factor;
        }
        
        current_distance += step_size;
        if (current_distance > max_distance || total_density > 3.0) break;
    }
    
    return total_density;
}

// Main ray marching function
vec3 xray_march(vec3 ray_origin, vec3 ray_direction) {
    float accumulated_density = 0.0;
    
    if (use_depth_method) {
        // Use depth buffer method (more accurate but view-dependent)
        accumulated_density = get_mesh_thickness_at_ray(ray_origin, ray_direction, max_distance);
    } else {
        // Use analytical approximation (works for simple shapes)
        accumulated_density = get_analytical_density(ray_origin, ray_direction);
    }
    
    // Convert density to X-ray appearance
    float xray_intensity = 1.0 - clamp(accumulated_density * 0.3, 0.0, 1.0);
    
    // Realistic X-ray coloring
    vec3 xray_color = vec3(xray_intensity * 0.9, xray_intensity * 0.95, xray_intensity);
    
    // Enhance contrast
    xray_color = pow(xray_color, vec3(0.8));
    
    return xray_color;
}

void fragment() {
    // Convert screen UV to normalized device coordinates
    vec2 ndc = (screen_uv * 2.0) - 1.0;

    // Calculate ray direction
    mat4 inv_projection = inverse(camera_projection);
    vec4 view_pos = inv_projection * vec4(ndc, -1.0, 1.0);
    view_pos /= view_pos.w;

    vec3 ray_direction = normalize((camera_transform * vec4(normalize(view_pos.xyz), 0.0)).xyz);
    vec3 ray_origin = camera_transform[3].xyz;

    // Perform X-ray ray marching
    vec3 xray_result = xray_march(ray_origin, ray_direction);
    
    COLOR = vec4(xray_result, 1.0);
}
