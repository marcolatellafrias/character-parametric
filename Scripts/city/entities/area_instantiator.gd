# AreaInstantiator.gd
extends Node3D
class_name AreaInstantiator

@export_group("Zone Geometry")
@export var height: float = 50.5
@export var segments: int = 16

@export var cameras: Array[Camera3D] = []
@export var world: Node3D

@export_group("Debug")
@export var debug_cylinder_color: Color = Color(0.0, 1.0, 0.0, 0.15)
@export var show_debug_cylinder: bool = false

@export_group("Lane Volume Visualization")
@export var show_lane_volumes: bool = false
@export var lane_volume_color: Color = Color(1.0, 0.5, 0.0)
@export var lane_volume_transparency: float = 0.2
@export var show_continuations: bool = false
@export var continuation_color: Color = Color(0.0, 1.0, 1.0)
@export var continuation_transparency: float = 0.3
@export var show_grid_points: bool = false
@export var grid_point_color: Color = Color(1.0, 1.0, 0.0)
@export var grid_point_size: float = 0.05
@export_range(1, 10) var granularity: int = 1

@export_group("Car Spawning")
@export var enable_car_spawning: bool = true
@export var spawn_interval: float = 0.15
@export var spawn_safety_margin: float = 3.0
@export var car_spacing: float = 12.5
@export var max_topup_per_tick: int = 5
@export var bootstrap_duration: float = 2.0
@export var bootstrap_batch_size: int = 30
@export_range(0.0, 1.0) var far_density_fraction: float = 0.1
@export_range(1.0, 8.0) var spawn_height_bias: float = 2.5
@export_flags_3d_physics var los_collision_mask: int = 1
@export_group("Fog")
@export var enable_fog: bool = true
@export var fog_shader: Shader

@export_group("Traffic Debug")
@export var show_traffic_debug: bool = false
@export var traffic_debug_corridors: bool = true
@export var traffic_debug_links: bool = true
@export var traffic_debug_stop_points: bool = true
@export var traffic_debug_tint: bool = true
@export var traffic_debug_labels: bool = true
@export var traffic_debug_cells: bool = false
@export var traffic_debug_label_distance: float = 30.0

var generator: GraphCityGenerator = null
var claim_registry: TrafficClaimRegistry = null
var car_manager: CarManager = null
var debug_cylinder_meshes: Array[MeshInstance3D] = []
var lane_volumes_container: Node3D
var grid_points_container: Node3D

var cylinder_areas: Array[Area3D] = []
var all_lane_volumes: Array[LaneVolume] = []
var volume_area_refs: Dictionary = {}

var spawn_timer: float = 0.0
var pending_seed_volumes: Array[LaneVolume] = []
var car_count: int = 0
var global_type_counts: Dictionary = {}
var volume_car_counts: Dictionary = {}
var car_volume_map: Dictionary = {}
var time_alive: float = 0.0

var fog_quad: MeshInstance3D = null
var fog_material: ShaderMaterial = null

func _ready() -> void:
	add_to_group("area_instantiator")

	var city_visualizer = get_tree().get_first_node_in_group("city_generator")
	if city_visualizer:
		generator = city_visualizer.get_generator()

	_setup_claim_registry()
	_setup_car_manager()
	_register_all_traffic_lights()
	_create_cylinder_areas()
	_setup_visualization_containers()
	_setup_fog()

	if show_debug_cylinder:
		_create_debug_cylinders()

	WorldSettings.settings_changed.connect(_on_settings_changed)

func _process(_delta: float) -> void:
	_update_cylinder_positions()
	_update_fog_position()

# Spawning runs in the physics step because visibility uses space queries
# (intersect_ray), which are only valid in a physics context.
func _physics_process(delta: float) -> void:
	if not enable_car_spawning or not world or not generator:
		return

	time_alive += delta
	_flush_pending_seeds()
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_topup_volumes()

func _exit_tree() -> void:
	_cleanup_containers()
	if fog_quad and is_instance_valid(fog_quad):
		fog_quad.queue_free()

# ============================================================================
# CLAIM REGISTRY
# ============================================================================

# One registry is shared by every instantiator (and every car), so cars
# spawned by different instantiators still see each other's claims.
func _setup_claim_registry() -> void:
	claim_registry = get_tree().get_first_node_in_group("traffic_claim_registry") as TrafficClaimRegistry
	if claim_registry:
		return
	claim_registry = TrafficClaimRegistry.new()
	claim_registry.name = "TrafficClaimRegistry"
	add_child(claim_registry)

	var drawer = TrafficDebugDrawer.new()
	drawer.name = "TrafficDebugDrawer"
	drawer.registry = claim_registry
	claim_registry.add_child(drawer)

# Like the registry, one manager is shared by every instantiator: it ticks the
# whole car fleet in a single loop and owns the pooled visuals.
func _setup_car_manager() -> void:
	car_manager = get_tree().get_first_node_in_group("car_manager") as CarManager
	if car_manager:
		return
	car_manager = CarManager.new()
	car_manager.name = "CarManager"
	add_child(car_manager)

# ============================================================================
# FOG
# ============================================================================

func _setup_fog() -> void:
	if not enable_fog or not fog_shader:
		return

	fog_material = ShaderMaterial.new()
	fog_material.shader = fog_shader
	fog_material.set_shader_parameter("inner_radius", WorldSettings.fog_start_distance)
	fog_material.set_shader_parameter("outer_radius", WorldSettings.render_distance)
	fog_material.set_shader_parameter("fog_color", WorldSettings.fog_color)
	fog_material.set_shader_parameter("player_pos", Vector3.ZERO)

	fog_quad = MeshInstance3D.new()
	fog_quad.name = "RadialFogQuad"
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)
	fog_quad.mesh = quad_mesh
	fog_quad.material_override = fog_material
	fog_quad.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	add_child(fog_quad)

func _update_fog_position() -> void:
	if not fog_material:
		return
	for camera in cameras:
		if camera and is_instance_valid(camera):
			fog_material.set_shader_parameter("player_pos", camera.global_position)
			return

func _on_settings_changed() -> void:
	if fog_material:
		fog_material.set_shader_parameter("inner_radius", WorldSettings.fog_start_distance)
		fog_material.set_shader_parameter("outer_radius", WorldSettings.render_distance)
		fog_material.set_shader_parameter("fog_color", WorldSettings.fog_color)

	_rebuild_cylinders()

# La cámara del/los jugador(es) local(es) se inyecta en runtime (el CharacterSpawner
# la pasa cuando spawnea el jugador y en cada respawn). Los cilindros de spawn se
# crean uno por cámara, así que hay que reconstruirlos al cambiar el set.
func set_cameras(new_cameras: Array[Camera3D]) -> void:
	cameras = new_cameras
	if is_inside_tree():
		_rebuild_cylinders()

func _rebuild_cylinders() -> void:
	for area in cylinder_areas:
		if area and is_instance_valid(area):
			area.queue_free()
	cylinder_areas.clear()
	volume_area_refs.clear()
	all_lane_volumes.clear()
	pending_seed_volumes.clear()
	_create_cylinder_areas()

	if show_debug_cylinder:
		_create_debug_cylinders()

# ============================================================================
# SETUP & CLEANUP
# ============================================================================

func _setup_visualization_containers() -> void:
	if not world:
		return

	# Deferred: _ready() can run while `world` is still adding its own children,
	# and add_child() is blocked during a parent's setup. Deferring lets the add
	# happen once world is idle. Building children on these containers before they
	# enter the tree is fine — the whole subtree attaches when the deferred call runs.
	lane_volumes_container = Node3D.new()
	lane_volumes_container.name = "LaneVolumesDebug_" + str(get_instance_id())
	world.add_child.call_deferred(lane_volumes_container)

	grid_points_container = Node3D.new()
	grid_points_container.name = "GridPointsDebug_" + str(get_instance_id())
	world.add_child.call_deferred(grid_points_container)

func _cleanup_containers() -> void:
	if claim_registry and is_instance_valid(claim_registry):
		_unregister_all_traffic_lights()

	if lane_volumes_container and is_instance_valid(lane_volumes_container):
		lane_volumes_container.queue_free()
	if grid_points_container and is_instance_valid(grid_points_container):
		grid_points_container.queue_free()

	for area in cylinder_areas:
		if area and is_instance_valid(area):
			area.queue_free()
	cylinder_areas.clear()

	for mesh in debug_cylinder_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	debug_cylinder_meshes.clear()

# ============================================================================
# CYLINDER TRACKING
# ============================================================================

func _create_cylinder_areas() -> void:
	for i in range(cameras.size()):
		var cylinder_area = Area3D.new()
		cylinder_area.name = "CylinderArea_" + str(i)
		cylinder_area.collision_layer = 0
		cylinder_area.collision_mask = 4
		cylinder_area.monitoring = true
		cylinder_area.monitorable = false

		var colliders = DebugUtil.create_cylinder_colliders(WorldSettings.spawn_radius, height, segments)
		for collider in colliders:
			cylinder_area.add_child(collider)

		var area_index = i
		cylinder_area.area_entered.connect(func(area): _on_cylinder_area_entered(area, area_index))
		cylinder_area.area_exited.connect(func(area): _on_cylinder_area_exited(area, area_index))

		add_child(cylinder_area)
		cylinder_areas.append(cylinder_area)

func _update_cylinder_positions() -> void:
	for i in range(min(cameras.size(), cylinder_areas.size())):
		var camera = cameras[i]
		var area = cylinder_areas[i]

		if camera and is_instance_valid(camera):
			area.global_position.x = camera.global_position.x
			area.global_position.z = camera.global_position.z
			area.global_position.y = 0

	if show_debug_cylinder:
		for i in range(cameras.size()):
			var camera = cameras[i]
			if not camera or not is_instance_valid(camera):
				continue
			for j in range(3):
				var mesh_idx = i * 3 + j
				if mesh_idx < debug_cylinder_meshes.size():
					var mesh = debug_cylinder_meshes[mesh_idx]
					if mesh and is_instance_valid(mesh):
						mesh.global_position.x = camera.global_position.x
						mesh.global_position.z = camera.global_position.z
						mesh.global_position.y = 0

func _on_cylinder_area_entered(area: Area3D, area_index: int) -> void:
	if area is LaneVolume:
		var vol_id = area.get_id()

		if not volume_area_refs.has(vol_id):
			volume_area_refs[vol_id] = []

		if not volume_area_refs[vol_id].has(area_index):
			volume_area_refs[vol_id].append(area_index)

		if not all_lane_volumes.has(area):
			all_lane_volumes.append(area)
			_update_visualization()
			# Seeding needs space queries, which can't run inside the
			# area_entered flush — queue it for the next physics tick.
			if time_alive > bootstrap_duration:
				pending_seed_volumes.append(area)

func _on_cylinder_area_exited(area: Area3D, area_index: int) -> void:
	if area is LaneVolume:
		var vol_id = area.get_id()

		if volume_area_refs.has(vol_id):
			var idx = volume_area_refs[vol_id].find(area_index)
			if idx != -1:
				volume_area_refs[vol_id].remove_at(idx)

			if volume_area_refs[vol_id].is_empty():
				volume_area_refs.erase(vol_id)

				var vol_idx = all_lane_volumes.find(area)
				if vol_idx != -1:
					all_lane_volumes.remove_at(vol_idx)
					_update_visualization()

# Los semáforos son estado estático del mundo: se registran todos una sola vez.
# Los cilindros de spawn son un anillo hueco en el borde de niebla — solo ven
# volúmenes que cruzan ese borde, nunca los cercanos al jugador, así que no
# sirven como señal de registro de semáforos.
func _register_all_traffic_lights() -> void:
	if claim_registry == null or generator == null:
		return
	for key in generator.lane_volume_areas:
		var vol: LaneVolume = generator.lane_volume_areas[key]
		if vol.get_traffic_plane():
			claim_registry.register_traffic_light(vol.get_traffic_plane())

func _unregister_all_traffic_lights() -> void:
	if claim_registry == null or generator == null:
		return
	for key in generator.lane_volume_areas:
		var vol: LaneVolume = generator.lane_volume_areas[key]
		if is_instance_valid(vol) and vol.get_traffic_plane():
			claim_registry.unregister_traffic_light(vol.get_traffic_plane())

# ============================================================================
# DISTANCE HELPERS
# ============================================================================

func get_min_camera_distance_xz(pos: Vector3) -> float:
	var min_dist = INF
	for camera in cameras:
		if not camera or not is_instance_valid(camera):
			continue
		var dist = Vector2(pos.x - camera.global_position.x, pos.z - camera.global_position.z).length()
		min_dist = min(min_dist, dist)
	return min_dist

# ============================================================================
# SPAWNING
# ============================================================================

# A point is hidden if, for every camera, it is beyond the fog wall or a
# static occluder (building, sidewalk, bridge) blocks the segment from the
# camera position to it. Only positions are used — never orientation — so
# turning the camera can't reveal a spawn, and in multiplayer the check
# depends solely on replicated player positions.
func _is_point_hidden(point: Vector3) -> bool:
	var space_state = get_world_3d().direct_space_state
	for camera in cameras:
		if not camera or not is_instance_valid(camera):
			continue
		var cam_pos = camera.global_position
		var dist = Vector2(point.x - cam_pos.x, point.z - cam_pos.z).length()
		if dist > WorldSettings.render_distance:
			continue
		var query = PhysicsRayQueryParameters3D.create(cam_pos, point, los_collision_mask)
		if space_state.intersect_ray(query).is_empty():
			return false
	return true

# The fractional part of the target is resolved by a per-volume die roll
# (hash of the volume id, stable across runs and machines): a street "worth"
# 0.4 cars carries one car on 40% of streets instead of always truncating to
# zero. Gives individual streets a fixed personality.
func _get_target_occupancy(vol: LaneVolume) -> int:
	var density = vol.get_traffic_density()
	var path_length = vol.get_path_length()
	var exact = density * path_length / car_spacing * _density_falloff(vol.get_center())
	var target = floori(exact)
	var volume_roll = float(hash(vol.get_id()) % 1024) / 1024.0
	if volume_roll < exact - target:
		target += 1
	return target

# Full density inside the clear zone, thinning linearly to far_density_fraction
# at the spawn edge. Ring area grows with radius squared, so without falloff
# most of the car budget lands where no player can see it.
func _density_falloff(pos: Vector3) -> float:
	var falloff_start = WorldSettings.fog_start_distance
	var falloff_end = WorldSettings.spawn_radius
	if falloff_end <= falloff_start:
		return 1.0
	var dist = get_min_camera_distance_xz(pos)
	var t = clamp((dist - falloff_start) / (falloff_end - falloff_start), 0.0, 1.0)
	return lerp(1.0, far_density_fraction, t)

func _flush_pending_seeds() -> void:
	for vol in pending_seed_volumes:
		if is_instance_valid(vol) and all_lane_volumes.has(vol):
			_seed_volume(vol)
	pending_seed_volumes.clear()

func _seed_volume(vol: LaneVolume) -> void:
	if car_count >= WorldSettings.max_cars:
		return
	var target = _get_target_occupancy(vol)
	var vol_id = vol.get_id()
	var current = volume_car_counts.get(vol_id, 0)
	for i in range(target - current):
		if car_count >= WorldSettings.max_cars:
			return
		_try_spawn_in_volume(vol, true)

func _topup_volumes() -> void:
	if car_count >= WorldSettings.max_cars:
		return
	var is_bootstrap = time_alive < bootstrap_duration
	var batch_limit = bootstrap_batch_size if is_bootstrap else max_topup_per_tick
	var spawned = 0
	for vol in all_lane_volumes:
		if spawned >= batch_limit or car_count >= WorldSettings.max_cars:
			break
		var target = _get_target_occupancy(vol)
		var vol_id = vol.get_id()
		var current = volume_car_counts.get(vol_id, 0)
		if current >= target:
			continue
		if _try_spawn_in_volume(vol, not is_bootstrap):
			spawned += 1

func _try_spawn_in_volume(vol: LaneVolume, check_visibility: bool) -> bool:
	var neighborhood_type = vol.get_neighborhood_type()
	var custom_weights = NeighborhoodTypes.get_car_weights(neighborhood_type)
	var car_seed = randi()

	# Same first draw the car will make in initialize_from_seed, so the
	# archetype can be checked against caps without allocating a car.
	var type_rng = RandomNumberGenerator.new()
	type_rng.seed = car_seed
	var car_type = CarArchetypes.select_type_seeded(type_rng, custom_weights)
	var archetype = CarArchetypes.get_archetype(car_type)

	if archetype.max_global != -1:
		if global_type_counts.get(car_type, 0) >= archetype.max_global:
			return false

	var v_max = vol.get_max_spawn_v()
	var v_min = archetype.min_spawn_v
	# Match the runtime claim radius (FlyingCar.SIDE_PADDING) so the spawn gap
	# check reserves the same side padding.
	var body_radius = Vector2(archetype.width, archetype.height).length() * 0.5 + FlyingCar.SIDE_PADDING

	# along_t is re-rolled per attempt so a partially visible street can
	# still spawn in its hidden sections.
	for attempt in range(5):
		var random_u = randf()
		# pow-shaped draw biases altitude toward the street: bias 1 = uniform,
		# higher = more ground traffic. min_spawn_v still holds for big vehicles.
		var random_v = v_min + pow(randf(), spawn_height_bias) * (v_max - v_min) if v_max > v_min else v_max
		var along_t = randf()

		var start_pos = vol.get_point_at_grid(random_u, random_v, true)
		var end_pos = vol.get_point_at_grid(random_u, random_v, false)
		var spawn_pos = start_pos.lerp(end_pos, along_t)

		# Widen by the side padding so the spawn position leaves the padded claim
		# inside the lane (same reservation the route walk applies downstream).
		var front_face = FlyingCar.compute_cross_section_face(spawn_pos, end_pos,
			archetype.width + 2.0 * FlyingCar.SIDE_PADDING, archetype.height)
		var validation = vol.validate_face_projection(front_face, random_u, random_v)

		if not validation["valid"]:
			continue

		var direction = (end_pos - spawn_pos).normalized()
		if not _is_spawn_position_free(spawn_pos, direction, archetype.depth, body_radius):
			continue

		# Bridges have no registry claims (cars clear them via their planned
		# profile), so reject in-slab spawns analytically instead.
		if _is_spawn_inside_bridge(vol, spawn_pos, direction, archetype):
			continue

		# Test the car's top — the last part a building stops occluding.
		if check_visibility and not _is_point_hidden(spawn_pos + Vector3.UP * archetype.height * 0.5):
			continue

		_spawn_car(vol, random_u, random_v, along_t, car_seed, custom_weights)
		return true

	return false

func _spawn_car(vol: LaneVolume, grid_u: float, grid_v: float,
				along_t: float, car_seed: int, custom_weights: Dictionary) -> void:
	var start_pos = vol.get_point_at_grid(grid_u, grid_v, true)
	var end_pos = vol.get_point_at_grid(grid_u, grid_v, false)
	var spawn_pos = start_pos.lerp(end_pos, along_t)

	var car = FlyingCar.new()
	car.world_node = world
	car.generator = generator
	car.area_instantiator = self
	car.claim_registry = claim_registry
	car.spawn_time = Time.get_ticks_msec() / 1000.0

	car.initialize_from_seed(car_seed, custom_weights)
	car.setup()

	car_count += 1
	_add_global_type(car.car_archetype)

	var vol_id = vol.get_id()
	_increment_volume_count(vol_id)
	car_volume_map[car.get_instance_id()] = vol_id

	car.volume_changed.connect(func(old_id: String, new_id: String):
		_decrement_volume_count(old_id)
		_increment_volume_count(new_id)
		car_volume_map[car.get_instance_id()] = new_id
	)

	# Emitted from dispose() while the car is still alive (cars are plain
	# Objects freed by the CarManager, so there is no tree_exited).
	car.despawned.connect(func():
		car_count -= 1
		_remove_global_type(car.car_archetype)
		var last_vol_id = car_volume_map.get(car.get_instance_id(), "")
		if last_vol_id != "":
			_decrement_volume_count(last_vol_id)
		car_volume_map.erase(car.get_instance_id())
	)

	car.set_path(
		spawn_pos,
		end_pos,
		0.0,
		grid_u,
		grid_v,
		vol.get_raw_data(),
		vol.width_cells,
		vol.height_cells
	)

	car_manager.add_car(car)

# Gap query against the claim registry (car bodies) instead of iterating
# every child of the world node.
func _is_spawn_position_free(spawn_pos: Vector3, direction: Vector3,
							 car_depth: float, body_radius: float) -> bool:
	if claim_registry == null:
		return true
	var half = direction * (car_depth * 0.5 + spawn_safety_margin)
	return claim_registry.is_capsule_free(spawn_pos - half, spawn_pos + half, body_radius)

# Exact skewed-box test (BridgePlanner) on the body plus a DENSE forward sweep
# to the gentle-climb runway (SPAWN_BRIDGE_RUNWAY): a car whose spawn altitude
# would meet a bridge within that distance can't ramp over it gently, so it
# spawns elsewhere. A car that TURNS into a bridged street mid-route climbs
# early on the previous street — but a spawn has no previous street, so this is
# where runway starvation must be caught. The old check sampled only 17/34/50u
# and slipped bridges through the gaps (the residual undershoot clips).
const SPAWN_BRIDGE_RUNWAY: float = 50.0   # = BridgePlanner MAX_RAMP
const SPAWN_BRIDGE_STEP: float = 4.0
func _is_spawn_inside_bridge(vol: LaneVolume, spawn_pos: Vector3,
							 direction: Vector3, archetype) -> bool:
	if generator == null:
		return false
	var v_margin: float = archetype.height * 0.5 + spawn_safety_margin
	var xz_margin: float = archetype.width * 0.5
	var half = direction * (archetype.depth * 0.5 + spawn_safety_margin)
	if BridgePlanner.point_blocked(generator, vol.face_idx, vol.edge_idx,
			spawn_pos - half, v_margin, xz_margin):
		return true
	var d := 0.0
	while d <= SPAWN_BRIDGE_RUNWAY:
		if BridgePlanner.point_blocked(generator, vol.face_idx, vol.edge_idx,
				spawn_pos + direction * d, v_margin, xz_margin):
			return true
		d += SPAWN_BRIDGE_STEP
	return false

# ============================================================================
# BOOKKEEPING
# ============================================================================

func _add_global_type(car_type: int) -> void:
	var current = global_type_counts.get(car_type, 0)
	global_type_counts[car_type] = current + 1

func _remove_global_type(car_type: int) -> void:
	var current = global_type_counts.get(car_type, 0)
	if current > 0:
		global_type_counts[car_type] = current - 1

func _increment_volume_count(vol_id: String) -> void:
	volume_car_counts[vol_id] = volume_car_counts.get(vol_id, 0) + 1

func _decrement_volume_count(vol_id: String) -> void:
	var current = volume_car_counts.get(vol_id, 0)
	if current > 1:
		volume_car_counts[vol_id] = current - 1
	else:
		volume_car_counts.erase(vol_id)

# ============================================================================
# VISUALIZATION
# ============================================================================

func _create_debug_cylinders() -> void:
	for mesh in debug_cylinder_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	debug_cylinder_meshes.clear()

	for i in range(cameras.size()):
		var inner_mesh = DebugUtil.create_debug_cylinder(Color(0.0, 1.0, 0.0, 0.1), WorldSettings.fog_start_distance, height, segments)
		inner_mesh.name = "DebugCylinder_Inner_" + str(i)
		add_child(inner_mesh)
		debug_cylinder_meshes.append(inner_mesh)

		var outer_mesh = DebugUtil.create_debug_cylinder(Color(1.0, 1.0, 0.0, 0.1), WorldSettings.render_distance, height, segments)
		outer_mesh.name = "DebugCylinder_Outer_" + str(i)
		add_child(outer_mesh)
		debug_cylinder_meshes.append(outer_mesh)

		var spawn_mesh = DebugUtil.create_debug_cylinder(Color(1.0, 0.0, 0.0, 0.1), WorldSettings.spawn_radius, height, segments)
		spawn_mesh.name = "DebugCylinder_Spawn_" + str(i)
		add_child(spawn_mesh)
		debug_cylinder_meshes.append(spawn_mesh)

func _update_visualization() -> void:
	if not lane_volumes_container or not grid_points_container:
		return

	for child in lane_volumes_container.get_children():
		child.queue_free()
	for child in grid_points_container.get_children():
		child.queue_free()

	var continuation_volumes: Array[LaneVolume] = []
	if show_continuations and generator:
		for vol in all_lane_volumes:
			var continuations = generator.get_lane_volume_continuations(vol.face_idx, vol.edge_idx)
			for cont in continuations:
				if not _volume_exists_in_array(cont, all_lane_volumes):
					continuation_volumes.append(cont)

	if show_lane_volumes:
		for vol in all_lane_volumes:
			var mesh = _create_volume_mesh(vol, lane_volume_color, lane_volume_transparency)
			if mesh:
				lane_volumes_container.add_child(mesh)

	if show_continuations:
		for cont_vol in continuation_volumes:
			var mesh = _create_volume_mesh(cont_vol, continuation_color, continuation_transparency)
			if mesh:
				lane_volumes_container.add_child(mesh)

	if show_grid_points:
		for vol in all_lane_volumes:
			_create_grid_points_for_volume(vol, grid_point_color)
		if show_continuations:
			for cont_vol in continuation_volumes:
				_create_grid_points_for_volume(cont_vol, continuation_color)

func _volume_exists_in_array(vol: LaneVolume, array: Array[LaneVolume]) -> bool:
	var vol_id = vol.get_id()
	for existing in array:
		if existing.get_id() == vol_id:
			return true
	return false

func _create_volume_mesh(vol: LaneVolume, color: Color, transparency: float) -> Node3D:
	return DebugUtil.create_skewed_cube_from_planes(
		vol.start_plane_vertices,
		vol.end_plane_vertices,
		color,
		transparency
	)

func _create_grid_points_for_volume(vol: LaneVolume, color: Color) -> void:
	var width_steps = vol.width_cells * granularity
	var height_steps = vol.height_cells * granularity

	for i in range(width_steps + 1):
		for j in range(height_steps + 1):
			var u = float(i) / float(width_steps) if width_steps > 0 else 0.0
			var v = float(j) / float(height_steps) if height_steps > 0 else 0.0

			var sphere_start = DebugUtil.create_debug_sphere_2dprint(Vector2i(i, j), color, grid_point_size)
			grid_points_container.add_child(sphere_start)
			sphere_start.global_position = vol.get_point_at_grid(u, v, true)

			var sphere_end = DebugUtil.create_debug_sphere_2dprint(Vector2i(i, j), color, grid_point_size)
			grid_points_container.add_child(sphere_end)
			sphere_end.global_position = vol.get_point_at_grid(u, v, false)
