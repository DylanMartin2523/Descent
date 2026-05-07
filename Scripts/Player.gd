extends CharacterBody3D

# Player components
@onready var neckNode: Node3D = $Neck
@onready var cameraNode: Camera3D = $Neck/Camera3D
@onready var crosshairNode: Node3D = $Neck/CrossHair

# Position markers for different stances
@onready var centerPosition: Marker3D = $Neck/CenterPosition
@onready var leanLeftPosition: Marker3D = $Neck/LeanLeft
@onready var leanRightPosition: Marker3D = $Neck/LeanRight
@onready var dropPoint: Marker3D = $Neck/Camera3D/Drop

# Collision shapes for different stances
@onready var standingCollision: CollisionShape3D = $StandingCol
@onready var crouchingCollision: CollisionShape3D = $CrouchingCol

# Detection raycasts
@onready var topDetection: RayCast3D = $TopDetect
@onready var rightDetection: RayCast3D = $RightDetect
@onready var leftDetection: RayCast3D = $LeftDetect
@onready var groundDetection: RayCast3D = $GroundDetect

# Stance position markers
@onready var crouchPosition: Marker3D = $Crouch
@onready var standingPosition: Marker3D = $Standing

# Movement speeds
var currentSpeed := 0.0
##Max speed when walking
@export var walkingSpeed = 4.0
##Max speed when running
@export var runningSpeed = 6.0
##Max speed when crouching
@export var crouchingSpeed = 2.0
##Speed when climbing ladders
@export var ladderSpeed = 1.2
##Jump Height
@export var jumpVelocity = 5.0

@export var speed = 50.0
@export var push_speed = 20.0
@export var turn_speed = 3.0
@export var friction = 0.98 # Lower is more slippery
@export var max_friction = 0.95
@export var gravity_acceleration = 130.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Mouse sensitivity and camera limits
@export var mouseSensitivity = 0.002
var cameraMinAngle = -80.0 * PI / 180.0
var cameraMaxAngle = 80.0 * PI / 180.0
var cameraRotation = Vector3.ZERO

var default_friction: float

var snap_timer = 0.0 # Time remaining where snapping is disabled

var world: WorldGen


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	default_friction = friction

# Handle mouse look and escape menu
func _unhandled_input(event: InputEvent) -> void:
	# Mouse look when captured
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Horizontal rotation (body)
		rotate_y(-event.relative.x * mouseSensitivity)

		# Vertical rotation (camera) with clamping
		cameraRotation.x -= event.relative.y * mouseSensitivity
		cameraRotation.x = clamp(cameraRotation.x, cameraMinAngle, cameraMaxAngle)
		neckNode.rotation = cameraRotation

# Handle stance changes and leaning
func _process(deltaTime: float) -> void:
	# Normal movement state
	if PlayerStats.currentState == 'Normal':
		# Crouching logic
		if Input.is_action_pressed("ui_control") or topDetection.is_colliding() == true:
			neckNode.global_position = lerp(neckNode.global_position, crouchPosition.global_position, 8  * deltaTime)
			standingCollision.disabled = true
			currentSpeed = crouchingSpeed
		else:
			neckNode.global_position = lerp(neckNode.global_position, standingPosition.global_position, 8  * deltaTime)
			standingCollision.disabled = false
			currentSpeed = walkingSpeed
	
			# Running logic
			if Input.is_action_pressed("ui_shift"):
				currentSpeed = runningSpeed
			else:
				currentSpeed = walkingSpeed
		
		# Leaning logic
		if Input.is_action_pressed("ui_q") and !leftDetection.is_colliding():
			cameraNode.transform = lerp(cameraNode.transform, leanLeftPosition.transform, 8  * deltaTime)
		elif Input.is_action_pressed("ui_e") and !rightDetection.is_colliding():
			cameraNode.transform = lerp(cameraNode.transform, leanRightPosition.transform, 8  * deltaTime)
		else:
			cameraNode.fov = 75
			cameraNode.transform = lerp(cameraNode.transform, centerPosition.transform, 8 * deltaTime)
	
	# Ladder climbing state
	elif PlayerStats.currentState == 'Ladder':
		standingCollision.disabled = true
		neckNode.global_position = lerp(neckNode.global_position, crouchPosition.global_position, 8 * deltaTime)
		cameraNode.fov = 75

# Handle movement physics
func _physics_process(delta: float) -> void:
	
	if snap_timer > 0:
		snap_timer -= delta
		
	# Normal movement
	if PlayerStats.currentState == 'Skiing':

			
		# Apply gravity when not on ground
		#if not is_on_floor():
		velocity += get_gravity() * delta

		# Jumping
		if Input.is_action_just_pressed("ui_accept") and is_on_floor():
			velocity.y += jumpVelocity
			snap_timer = 0.2 # Disable snapping for 200ms

		if not is_on_floor():
			velocity.y -= gravity * delta

		# 2. Handle Steering
		var input_dir = Input.get_axis("ui_left", "ui_right")
		rotate_y(-input_dir * turn_speed * delta)

		# 3. Grounded Logic (The Parallel Vector)
		if groundDetection.is_colliding():
			var n = groundDetection.get_collision_normal()
			
			# Align the character model to the slope visually
			align_with_normal(n, delta)
			
			# Calculate the 'Forward' vector parallel to the ground
			var forward = -global_transform.basis.z
			var parallel_forward = forward.slide(n).normalized()
			
			# Apply acceleration along that parallel vector
			# Note: Going downhill naturally increases speed because gravity pulls 'y' 
			# and move_and_slide() converts that into forward momentum on slopes.
			var fall_line = Vector3.DOWN.slide(n).normalized()
			
			var turn_mod = parallel_forward.dot(fall_line)
			
			var velo_length = velocity.length()
			
			if velo_length > 5.0:
				velocity += parallel_forward * (speed  * (1 - turn_mod)) * delta
			
			var abs_turn_mod = abs(turn_mod)
			var low_velo = 1.0
			var low_turn_mod = 0.8
			if velo_length < low_velo and abs_turn_mod < low_turn_mod:
				friction = default_friction - ((1 - (velo_length / low_velo)) * 0.6) - ((1 - (abs_turn_mod / low_turn_mod)) * 0.4)
				#velocity *= 
			else:
				friction = default_friction
				fall_line *= abs_turn_mod
			# 2. Calculate Steepness (0.0 to 1.0)
			# If n.y is 1, steepness is 0. If n.y is 0.5, steepness is 0.5.
			var steepness = 1.0 - n.y

			# 3. Apply Slope Acceleration
			# This makes you speed up automatically when facing downhill
			velocity += fall_line * steepness * gravity_acceleration * delta
			
			if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
				input_dir = Input.get_axis("ui_up", "ui_down")
				if velocity.length() < 5.0:
					forward = global_transform.basis.z.slide(n) * input_dir
					velocity += forward * push_speed * delta
			
			prints('turn mod', turn_mod, velocity.length())
			# Apply Friction (Slippery feel)
			velocity *= friction


	if PlayerStats.currentState == 'Walking':
		# Horizontal movement
		var inputDirection := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var movementDirection := (transform.basis * Vector3(inputDirection.x, 0, inputDirection.y)).normalized()
		
		if movementDirection:
			velocity.x = movementDirection.x * currentSpeed
			velocity.z = movementDirection.z * currentSpeed
		else:
			velocity.x = 0
			velocity.z = 0

	# Ladder climbing movement
	elif PlayerStats.currentState == 'Ladder':
		if Input.is_action_pressed("ui_up"):
			velocity.y = ladderSpeed
		elif Input.is_action_pressed("ui_down"):
			velocity.y = - ladderSpeed
		else:
			velocity.y = move_toward(velocity.y, 0, currentSpeed) 
		
	if snap_timer <= 0:
		apply_floor_snap()

	move_and_slide()


func align_with_normal(n: Vector3, delta: float):
	# Gradually tilt the basis to match the ground normal
	var target_basis = global_transform.basis
	target_basis.y = n
	target_basis.x = -target_basis.z.cross(n)
	target_basis = target_basis.orthonormalized()
	
	global_transform.basis = global_transform.basis.slerp(target_basis, 10.0 * delta)
	
#func align_with_normal(xform, n):
	#xform.basis.y = n
	#xform.basis.x = -xform.basis.z.cross(n) # Calculate right vector
	#xform.basis = xform.basis.orthonormalized()
	#return xform
