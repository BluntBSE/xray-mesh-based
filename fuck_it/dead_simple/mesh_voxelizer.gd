extends Node
#class_name MeshVoxelizer

# Convert a MeshInstance3D to a 3D texture representing its interior density
static func voxelize_mesh(mesh_instance: MeshInstance3D, resolution: int = 64) -> ImageTexture3D:
    if not mesh_instance or not mesh_instance.mesh:
        print("Error: Invalid mesh instance")
        return null
    
    var mesh = mesh_instance.mesh
    var aabb = mesh.get_aabb()
    print("Voxelizing mesh with AABB: ", aabb)
    print("Resolution: ", resolution)
    
    # Create array of images for each Z slice
    var images: Array[Image] = []
    var total_inside = 0
    var total_voxels = 0
    
    for z in range(resolution):
        # Create 2D image for this Z slice
        var slice_data = PackedByteArray()
        slice_data.resize(resolution * resolution)
        
        for y in range(resolution):
            for x in range(resolution):
                # Convert voxel coordinates to local position
                var local_pos = Vector3(
                    aabb.position.x + (float(x) / resolution) * aabb.size.x,
                    aabb.position.y + (float(y) / resolution) * aabb.size.y,
                    aabb.position.z + (float(z) / resolution) * aabb.size.z
                )
                
                # Test if point is inside mesh
                var is_inside = is_point_inside_mesh(local_pos, mesh)
                var pixel_index = x + y * resolution
                slice_data[pixel_index] = 255 if is_inside else 0
                
                if is_inside:
                    total_inside += 1
                total_voxels += 1
        
        # Create image for this slice
        var slice_image = Image.create_from_data(resolution, resolution, false, Image.FORMAT_R8, slice_data)
        images.append(slice_image)
    
    print("Voxelization complete: ", total_inside, "/", total_voxels, " voxels inside mesh (", float(total_inside)/total_voxels * 100.0, "%)")
    
    # Create 3D texture from image array
    var texture_3d = ImageTexture3D.new()
    texture_3d.create(Image.FORMAT_R8, resolution, resolution, resolution, false, images)
    
    return texture_3d

# Ray-casting based point-in-mesh test
static func is_point_inside_mesh(point: Vector3, mesh: Mesh) -> bool:
    # Cast ray from point in random direction
    var ray_direction = Vector3(1, 0.1, 0.1).normalized()  # Slightly off-axis to avoid edge cases
    var intersection_count = 0
    
    # Get mesh arrays
    if mesh.get_surface_count() == 0:
        return false
        
    var arrays = mesh.surface_get_arrays(0)
    var vertices = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
    var indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
    
    if not vertices or not indices:
        return false
    
    # Test ray against all triangles
    for i in range(0, indices.size(), 3):
        var v0 = vertices[indices[i]]
        var v1 = vertices[indices[i + 1]]
        var v2 = vertices[indices[i + 2]]
        
        if ray_triangle_intersect(point, ray_direction, v0, v1, v2):
            intersection_count += 1
    
    # Odd number of intersections = inside
    return (intersection_count % 2) == 1

# Ray-triangle intersection test (Möller-Trumbore algorithm)
static func ray_triangle_intersect(ray_origin: Vector3, ray_dir: Vector3, v0: Vector3, v1: Vector3, v2: Vector3) -> bool:
    var edge1 = v1 - v0
    var edge2 = v2 - v0
    var h = ray_dir.cross(edge2)
    var a = edge1.dot(h)
    
    if abs(a) < 0.0001:
        return false  # Ray is parallel to triangle
    
    var f = 1.0 / a
    var s = ray_origin - v0
    var u = f * s.dot(h)
    
    if u < 0.0 or u > 1.0:
        return false
    
    var q = s.cross(edge1)
    var v = f * ray_dir.dot(q)
    
    if v < 0.0 or u + v > 1.0:
        return false
    
    var t = f * edge2.dot(q)
    return t > 0.0001  # Ray intersects triangle
