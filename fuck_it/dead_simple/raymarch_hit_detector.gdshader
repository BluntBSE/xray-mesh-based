shader_type canvas_item;

// Camera uniforms - we'll pass these from GDScript
uniform mat4 camera_transform;
uniform mat4 camera_projection;
uniform vec2 screen_size;

// Mesh data uniforms
uniform sampler2D vertex_texture : filter_nearest;
uniform mat4 mesh_transform;
uniform int triangle_count;
uniform int texture_width;

// Spatial grid uniforms
uniform sampler2D grid_texture : filter_nearest;
uniform int grid_resolution;
uniform vec3 grid_min_bound;
uniform vec3 grid_max_bound;

varying vec2 screen_uv;

void vertex() {
    screen_uv = UV;
}

// Ray-triangle intersection using Möller-Trumbore algorithm
bool ray_triangle_intersect(vec3 ray_origin, vec3 ray_dir, vec3 v0, vec3 v1, vec3 v2, out float t) {
    const float EPSILON = 1e-8;
    
    vec3 edge1 = v1 - v0;
    vec3 edge2 = v2 - v0;
    vec3 h = cross(ray_dir, edge2);
    float a = dot(edge1, h);
    
    if (a > -EPSILON && a < EPSILON) {
        return false; // Ray is parallel to triangle
    }
    
    float f = 1.0 / a;
    vec3 s = ray_origin - v0;
    float u = f * dot(s, h);
    
    if (u < 0.0 || u > 1.0) {
        return false;
    }
    
    vec3 q = cross(s, edge1);
    float v = f * dot(ray_dir, q);
    
    if (v < 0.0 || u + v > 1.0) {
        return false;
    }
    
    t = f * dot(edge2, q);
    return t > EPSILON; // Only count forward intersections
}

// Get triangle vertices from texture
void get_triangle_vertices(int triangle_idx, out vec3 v0, out vec3 v1, out vec3 v2) {
    int base_idx = triangle_idx * 3;
    
    // Get v0
    int pixel_idx = base_idx;
    int x = pixel_idx % texture_width;
    int y = pixel_idx / texture_width;
    vec3 vertex = texelFetch(vertex_texture, ivec2(x, y), 0).rgb;
    v0 = (mesh_transform * vec4(vertex, 1.0)).xyz;
    
    // Get v1
    pixel_idx = base_idx + 1;
    x = pixel_idx % texture_width;
    y = pixel_idx / texture_width;
    vertex = texelFetch(vertex_texture, ivec2(x, y), 0).rgb;
    v1 = (mesh_transform * vec4(vertex, 1.0)).xyz;
    
    // Get v2
    pixel_idx = base_idx + 2;
    x = pixel_idx % texture_width;
    y = pixel_idx / texture_width;
    vertex = texelFetch(vertex_texture, ivec2(x, y), 0).rgb;
    v2 = (mesh_transform * vec4(vertex, 1.0)).xyz;
}

// Get grid cell density (simplified spatial acceleration)
float get_grid_density(vec3 world_pos) {
    vec3 grid_pos = (world_pos - grid_min_bound) / (grid_max_bound - grid_min_bound);
    
    if (any(lessThan(grid_pos, vec3(0.0))) || any(greaterThan(grid_pos, vec3(1.0)))) {
        return 0.0; // Outside grid
    }
    
    ivec3 cell = ivec3(grid_pos * float(grid_resolution));
    cell = clamp(cell, ivec3(0), ivec3(grid_resolution - 1));
    
    int y = cell.y * grid_resolution + cell.z; // Flatten 3D to 2D
    if (y >= grid_resolution * grid_resolution) return 0.0;
    
    return texelFetch(grid_texture, ivec2(cell.x, y), 0).r;
}

// Optimized intersection counting using spatial acceleration
int count_mesh_intersections_optimized(vec3 ray_origin, vec3 ray_dir) {
    // For now, use grid density as a proxy for inside/outside
    // In a full implementation, we'd traverse the grid and only test triangles in relevant cells
    float density = get_grid_density(ray_origin);
    
    // More sensitive threshold for smoother results
    return (density > 0.05) ? 1 : 0; // Lower threshold for better detection
}

// Ray marching function - now with mesh intersection for X-ray effect
vec3 ray_march(vec3 ray_origin, vec3 ray_direction) {
    float total_distance = 0.0;
    float accumulated_density = 0.0;
    vec3 current_pos = ray_origin;

    // Higher quality settings for smoother results
    float material_density = 0.8;
    float step_size = 0.02; // Much smaller steps for smoother results

    for (int i = 0; i < 200; i++) { // More iterations for higher quality
        current_pos = ray_origin + ray_direction * total_distance;
        
        // Use optimized spatial acceleration instead of full triangle testing
        int intersections = count_mesh_intersections_optimized(current_pos, ray_direction);
        bool inside_mesh = intersections > 0; // Simplified inside/outside test
        
        if (inside_mesh) {
            accumulated_density += material_density * step_size;
        }
        
        total_distance += step_size;
        
        // Stop if we've gone too far or accumulated too much density
        if (total_distance > 5.0 || accumulated_density > 2.0) {
            break;
        }
    }

    // Convert accumulated density to color
    float intensity = clamp(accumulated_density, 0.0, 1.0);
    return vec3(intensity * 0.8, intensity * 0.9, intensity); // Slightly blue-tinted
}

void fragment() {
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
