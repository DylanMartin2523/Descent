@tool
extends MeshInstance3D
class_name TerrainGenerator

@export_tool_button("Generate Landscape", "WorldEnvironment") var generate = _generate_terrain
@export var save_mesh_path = "res://TerrainData/Terrain.res"

## Terrain Generation Settings
@export var subdivides : int = 50
@export var heightmap: Texture2D
@export var height_scale: float = 5.0  # Maximum vertical exaggeration of the terrain
@export var mesh_size: Vector2 = Vector2(100.0, 100.0) # Size of the base plane in world units (X and Z)
@export var noise_texture: NoiseTexture2D
@export var noise_strength: float = 0.3  # How much noise affects the final height (0.0 - 1.0)

#@onready var snow_texture = $"../Camera3D/SubViewport"

var image_data: Image = Image.new()
var noise_data: Image = Image.new()

var world: WorldGen

func _ready():
	if not Engine.is_editor_hint():
		# Ensure generation runs after basic setup (though deferred call is commented out, 
		# direct call is often fine for editor tools or simple setup)
		# call_deferred("_generate_terrain")
		_generate_terrain()

func _generate_terrain():
	# 1. Load the heightmap texture
	if not await load_heightmap():
		return

	var plane = PlaneMesh.new()
	plane.subdivide_depth = subdivides
	plane.subdivide_width = subdivides

	var plane_mesh = plane

	# Set the plane dimensions based on the specified world size and heightmap aspect ratio
	var img_size = image_data.get_size()
	var aspect_ratio = float(img_size.x) / float(img_size.y)

	# Set width (X) based on mesh_size.x, calculate height (Z) based on aspect ratio
	plane_mesh.size = Vector2(mesh_size.x, mesh_size.y * aspect_ratio)


	# Apply material override if one is set (useful for initial visualization)
	if material_override:
		self.set_surface_override_material(0, material_override)

	# 3. Get mesh data and modify vertices
	generate_terrain_from_heightmap(plane_mesh)

func smooth_terrain(vertices: PackedVector3Array, grid_size: int, iterations: int = 1) -> PackedVector3Array:
	var smoothed_vertices = vertices.duplicate()
	
	for iter in range(iterations):
		# We skip the very outer edges to avoid array out-of-bounds errors
		for z in range(1, grid_size - 1):
			for x in range(1, grid_size - 1):
				var i = z * grid_size + x
				
				# Get the heights of the 4 direct neighbors
				var h_up = vertices[i - grid_size].y
				var h_down = vertices[i + grid_size].y
				var h_left = vertices[i - 1].y
				var h_right = vertices[i + 1].y
				
				# Average them out with the current vertex
				var avg_height = (vertices[i].y + h_up + h_down + h_left + h_right) / 5.0
				smoothed_vertices[i].y = avg_height
				
		# Copy back for the next iteration
		vertices = smoothed_vertices.duplicate()
		
	return smoothed_vertices
	
## Step 1: Load the heightmap texture file
func load_heightmap() -> bool:
	image_data = heightmap.get_image()
	if image_data.get_width() < 512:
		image_data.resize(512, 512, Image.INTERPOLATE_CUBIC)
	image_data.convert(Image.FORMAT_RF)

	if noise_texture:
		# Poll until the noise texture has finished generating
		while noise_texture.get_image() == null:
			await get_tree().process_frame
		
		noise_data = noise_texture.get_image()
		if noise_data.get_width() < 512:
			noise_data.resize(512, 512, Image.INTERPOLATE_CUBIC)
		noise_data.convert(Image.FORMAT_RF)

	return true
## Step 2 & 3: Generate Geometry from Heightmap Data
func generate_terrain_from_heightmap(plane_mesh: PlaneMesh):
	# Get the base mesh arrays from the PlaneMesh configuration
	var arrays = ArrayMesh.new()
	var mesh_data = plane_mesh.get_mesh_arrays()

	# We are primarily interested in the vertices array
	var vertices: PackedVector3Array = mesh_data[Mesh.ARRAY_VERTEX]

	if vertices.is_empty():
		push_error("The base plane mesh has no vertices to modify.")
		return

	var img_size = image_data.get_size()
	# UV scaling factors are typically not needed here since we calculate UVs manually from normalized position
	var uv_scale_x = 1.0 / float(img_size.x)
	var uv_scale_y = 1.0 / float(img_size.y)

	# Iterate through all vertices and displace them along the Y-axis based on heightmap data
	for i in range(vertices.size()):
		var vertex = vertices[i]

		# 1. Calculate normalized UV coordinates (0.0 to 1.0) for this vertex position.
		# PlaneMesh vertices span from (-0.5*size) to (0.5*size) in X/Z. 
		# We normalize this range to fit the texture coordinates (0.0 to 1.0).
		var normalized_u = (vertex.x / plane_mesh.size.x) + 0.5
		var normalized_v = (vertex.z / plane_mesh.size.y) + 0.5

		# 2. Determine which heightmap pixel corresponds to this vertex
		var pixel_x = int(normalized_u * img_size.x)
		var pixel_y = int(normalized_v * img_size.y)

		# Clamp coordinates to ensure they are within image bounds
		pixel_x = clamp(pixel_x, 0, img_size.x - 1)
		pixel_y = clamp(pixel_y, 0, img_size.y - 1)

		# 3. Get the pixel color (height value)
		# We assume the heightmap is grayscale, using the Red channel as height magnitude (0.0 to 1.0)
		var pixel_color: Color = image_data.get_pixel(pixel_x, pixel_y)
		var height_value = pixel_color.r

		if noise_data and not noise_data.is_empty():
			var noise_pixel = noise_data.get_pixel(pixel_x, pixel_y)
			height_value = lerp(height_value, height_value + noise_pixel.r - 0.5, noise_strength)
			height_value = clamp(height_value, 0.0, 1.0)

	
		# 4. Displace the vertex along the Y-axis
		# Final Height = (Normalized Height Value * Maximum Scale Factor)
		vertex.y = height_value * height_scale

		# Update the vertex in the array
		vertices[i] = vertex


	var grid_size = plane_mesh.subdivide_width + 2
	vertices = smooth_terrain(vertices, grid_size, 2)

	# ADD THIS LINE:
	mesh_data[Mesh.ARRAY_VERTEX] = vertices

	var new_mesh = ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data)
	# Calculate smooth normals for the new mesh geometry
	var tool = SurfaceTool.new()
	tool.create_from(new_mesh, 0)
	tool.generate_normals()
	var final_mesh = tool.commit()

	# Assign the newly generated mesh to the MeshInstance3D node
	self.mesh = final_mesh
	
	self.mesh.material = ShaderMaterial.new()
	self.mesh.material.set_script("res://Scripts/terrain_generation/Shaders/snow.gdshader")
	
	if world != null:
		mesh.material.set_shader_parameter('viewport_texture', world.snow_viewport)
	else:
		mesh.material.set_shader_parameter('viewport_texture', $"../Camera3D/SubViewport")
	mesh.material.set_shader_parameter('floor_texture', "res://assets/textures/grass02.jpg")
	
	var image_texture = ImageTexture.create_from_image(image_data)
	
	mesh.material.set_shader_parameter('floor_heightmap', image_texture)
	

	print("Terrain generation complete.")
	if Engine.is_editor_hint():
		await get_tree().create_timer(0.5).timeout
		save_data()
	else:
		# Automatically create a collision shape based on the new geometry
		_generate_collision_shape()
		

func _generate_collision_shape():
	var collision = CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	
	var static_body = StaticBody3D.new()
	static_body.add_child(collision)
	for i in range(20):
		static_body.set_collision_layer_value(i, true)
		static_body.set_collision_mask_value(i, true)
	add_child(static_body)

func save_data():
	var folder = save_mesh_path.replace(save_mesh_path.get_file(), "")
	var dir = DirAccess.open(folder)
	if dir == null:
		DirAccess.make_dir_absolute(folder)
		dir = DirAccess.open(folder)
	
	var error = ResourceSaver.save(mesh, save_mesh_path)
	
	if error == OK:
		print("Mesh successfully saved to: ", save_mesh_path)
	else:
		printerr("Error saving Mesh: ", error)
