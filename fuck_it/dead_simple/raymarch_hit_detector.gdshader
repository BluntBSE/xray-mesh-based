shader_type canvas_item;

// Camera uniforms - we'll pass these from GDScript
uniform mat4 camera_transform;
uniform mat4 camera_projection;
uniform vec2 screen_size;

varying vec2 screen_uv;

void vertex() {
    screen_uv = UV;
}

// Simple ray-sphere intersection for now (we'll expand this)
float sphere_sdf(vec3 point, vec3 center, float radius) {
    return length(point - center) - radius;
}

// Cone SDF - much better for debugging X-ray density
float cone_sdf(vec3 point, vec3 tip, vec3 base_center, float base_radius, float height) {
    // Simple cone: just interpolate radius based on height
    vec3 to_point = point - tip;
    float y_dist = to_point.y; // Distance along cone axis (should be negative for inside cone)

    // If above tip or below base, we're outside
    if (y_dist > 0.0 || y_dist < -height) {
        return 1.0; // Outside
    }

    // Calculate radius at this height
    float t = abs(y_dist) / height; // 0 at tip, 1 at base
    float radius_at_height = base_radius * t;

    // Distance from center axis
    float radial_dist = length(to_point.xz);

    // Distance to cone surface
    return radial_dist - radius_at_height;
}// Ray marching function - now with density accumulation for X-ray effect
vec3 ray_march(vec3 ray_origin, vec3 ray_direction) {
    float total_distance = 0.0;
    float accumulated_density = 0.0;
    vec3 current_pos = ray_origin;

    // Density properties for the cones - adjusted for smoother results
    float material_density = 0.8; // Reduced for smoother gradients
    float step_size = 0.04; // Smaller steps to reduce banding

    // First cone parameters: tip at (0,2,0), base at (0,-2,0), radius 2
    vec3 cone1_tip = vec3(0.0, 2.0, 0.0);
    vec3 cone1_base = vec3(0.0, -2.0, 0.0);
    float cone1_base_radius = 2.0;
    float cone1_height = 4.0;

    // Second cone parameters: positioned behind and slightly offset for overlap
    vec3 cone2_tip = vec3(1.5, 1.5, -3.0);   // Offset and behind first cone
    vec3 cone2_base = vec3(1.5, -2.5, -3.0); // Same X offset, extends lower
    float cone2_base_radius = 1.8;            // Slightly smaller
    float cone2_height = 4.0;

    for (int i = 0; i < 120; i++) { // More iterations for smoother results
        // Check distance to both cones
        float distance1 = cone_sdf(current_pos, cone1_tip, cone1_base, cone1_base_radius, cone1_height);
        float distance2 = cone_sdf(current_pos, cone2_tip, cone2_base, cone2_base_radius, cone2_height);

        // Use the minimum distance (closest surface) for marching
        float distance_to_surface = min(distance1, distance2);

        // Accumulate density from first cone
        if (distance1 < 0.0) {
            float depth_factor1 = abs(distance1) / cone1_base_radius;
            float y_normalized1 = (current_pos.y - cone1_tip.y) / (-cone1_height);
            float thickness_factor1 = y_normalized1;
            accumulated_density += material_density * step_size * (0.5 + depth_factor1 * 0.3 + thickness_factor1 * 0.7);
        }

        // Accumulate density from second cone (additive for overlap)
        if (distance2 < 0.0) {
            float depth_factor2 = abs(distance2) / cone2_base_radius;
            float y_normalized2 = (current_pos.y - cone2_tip.y) / (-cone2_height);
            float thickness_factor2 = y_normalized2;
            accumulated_density += material_density * step_size * (0.5 + depth_factor2 * 0.3 + thickness_factor2 * 0.7);
        }

        // Always use consistent step size for smoother marching
        float march_distance = distance_to_surface < 0.0 ? step_size : max(distance_to_surface * 0.5, step_size);

        current_pos += ray_direction * march_distance;
        total_distance += march_distance;

        // Stop if we've marched too far
        if (total_distance > 30.0) { // Increased range for second cone
            break;
        }
    }

    // Convert accumulated density to green intensity with gentler curve
    float intensity = 1.0 - exp(-accumulated_density * 0.3); // Gentler exponential for smoother gradients
    return vec3(0.0, intensity, 0.0);
}void fragment() {
    // Convert screen UV to normalized device coordinates
    vec2 ndc = (screen_uv * 2.0) - 1.0;

    // Get the inverse projection matrix to properly calculate ray direction
    mat4 inv_projection = inverse(camera_projection);

    // Transform NDC to view space
    vec4 view_pos = inv_projection * vec4(ndc, -1.0, 1.0);
    view_pos /= view_pos.w;

    // Calculate ray direction in world space
    vec3 ray_direction = normalize((camera_transform * vec4(normalize(view_pos.xyz), 0.0)).xyz);
    vec3 ray_origin = camera_transform[3].xyz; // Camera position from transform matrix

    vec3 color = ray_march(ray_origin, ray_direction);
    COLOR = vec4(color, 1.0);
}
