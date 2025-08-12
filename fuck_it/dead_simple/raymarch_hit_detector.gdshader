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
uniform int triangles_per_cell;

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

// Spatially accelerated point-in-mesh testing
bool is_point_inside_mesh_spatial(vec3 point) {
    // Convert world position to grid coordinates
    vec3 grid_pos = (point - grid_min_bound) / (grid_max_bound - grid_min_bound);
    
    if (any(lessThan(grid_pos, vec3(0.0))) || any(greaterThan(grid_pos, vec3(1.0)))) {
        return false; // Outside grid bounds
    }
    
    ivec3 cell = ivec3(grid_pos * float(grid_resolution));
    cell = clamp(cell, ivec3(0), ivec3(grid_resolution - 1));
    
    // Calculate base offset in the grid texture for this cell
    int base_y = (cell.y * grid_resolution + cell.z) * triangles_per_cell;
    
    // Cast ray to test inside/outside
    vec3 test_ray_dir = normalize(vec3(1.0, 0.37, 0.73));
    int intersection_count = 0;
    
    // Test only triangles in this grid cell
    for (int i = 0; i < triangles_per_cell; i++) {
        int pixel_y = base_y + i;
        
        // Get triangle index from grid texture
        float triangle_id = texelFetch(grid_texture, ivec2(cell.x, pixel_y), 0).r;
        
        // End of list marker
        if (triangle_id < 0.0) break;
        
        int triangle_idx = int(triangle_id);
        if (triangle_idx >= triangle_count) break;
        
        // Get triangle vertices and test intersection
        vec3 v0, v1, v2;
        get_triangle_vertices(triangle_idx, v0, v1, v2);
        
        float t;
        if (ray_triangle_intersect(point, test_ray_dir, v0, v1, v2, t)) {
            intersection_count++;
        }
    }
    
    // Odd number of intersections = inside
    return (intersection_count % 2) == 1;
}

// Spatially accelerated ray marching
vec3 ray_march(vec3 ray_origin, vec3 ray_direction) {
    float total_distance = 0.0;
    float accumulated_density = 0.0;
    
    float material_density = 0.8;
    float step_size = 0.03; // Smaller steps again since we're much faster now
    float max_distance = 5.0;
    
    // More iterations since each step is much cheaper
    for (int i = 0; i < 1500; i++) {
        vec3 current_pos = ray_origin + ray_direction * total_distance;
        
        // Early exit if outside mesh bounds
        vec3 bounds_check = (current_pos - grid_min_bound) / (grid_max_bound - grid_min_bound);
        if (any(lessThan(bounds_check, vec3(-0.1))) || any(greaterThan(bounds_check, vec3(1.1)))) {
            total_distance += step_size;
            if (total_distance > max_distance) break;
            continue;
        }
        
        // Spatially accelerated inside/outside test
        bool inside_mesh = is_point_inside_mesh_spatial(current_pos);
        
        if (inside_mesh) {
            accumulated_density += material_density * step_size;
        }
        
        total_distance += step_size;
        
        // Stop if we've gone too far or accumulated too much density
        if (total_distance > max_distance || accumulated_density > 2.0) {
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
