extends Node3D
class_name AreaInstantiator

@export var outer_radius: float = 20.0
@export var inner_radius: float = 5.5
@export var height: float = 15.0
@export var segments: int = 16
@export var debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
@export var show_debug: bool = false

@export var world: Node3D
@export var spawn_interval: float = 0.3
@export var max_spawn_attempts: int = 50

@export_group("Car Size Ranges")
@export var debug_size_factor: float = 1.0
@export var min_car_width: float = 1.5 * debug_size_factor
@export var max_car_width: float = 2.5 * debug_size_factor
@export var min_car_height: float = 0.8 * debug_size_factor
@export var max_car_height: float = 1.5 * debug_size_factor
@export var min_car_depth: float = 3.0 * debug_size_factor
@export var max_car_depth: float = 5.0 * debug_size_factor

var debug_mesh: MeshInstance3D
var city = null
var valid_segments: Array = []
var spawn_timer_accumulator: float = 0.0

func _ready() -> void:
    city = get_tree().get_first_node_in_group("city_generator")
    
    if show_debug:
        _create_debug_visualization()

func _process(delta: float) -> void:
    if city != null:
        _update_valid_segments()
        
        if show_debug:
            _refresh_debug_visualization()
        
        # Acumular tiempo para spawn
        spawn_timer_accumulator += delta
        if spawn_timer_accumulator >= spawn_interval:
            spawn_timer_accumulator -= spawn_interval
            _spawn_car()

func _create_debug_visualization() -> void:
    _refresh_debug_visualization()

func _spawn_car() -> void:
    if not world or not city:
        return
    
    if valid_segments.is_empty():
        return
    
    # Intentar spawnear en un segmento válido
    var spawn_data = _get_random_valid_path()
    
    if spawn_data == null:
        return
    
    # Spawn del car
    var car = FlyingCar.new()
    car.width = randf_range(min_car_width, max_car_width)
    car.height = randf_range(min_car_height, max_car_height)
    car.depth = randf_range(min_car_depth, max_car_depth)
    car.car_color = Color(randf(), randf(), randf(), 1.0)
    
    world.add_child(car)
    car.global_position = spawn_data["spawn_position"]
    
    # Orientar el auto hacia el end_position
    var direction = (spawn_data["end_position"] - spawn_data["start_position"]).normalized()
    if direction.length() > 0.001:
        car.look_at(spawn_data["end_position"], Vector3.UP)
    
    # Configurar el path completo desde start a end
    car.set_path(spawn_data["start_position"], spawn_data["end_position"])

func _update_valid_segments() -> void:
    valid_segments.clear()
    
    # Obtener lane volumes cercanos
    var volumes = city.get_lane_volumes_in_cylindrical_area(
        global_position,
        outer_radius * 1.5,
        height
    )
    
    if volumes.is_empty():
        return
    
    # Para cada segmento del anillo, verificar si intersecta con algún lane volume
    for i in range(segments):
        var segment_vertices = _get_segment_vertices(i)
        
        for vol in volumes:
            if _segment_intersects_volume(segment_vertices, vol["start_plane_vertices"], vol["end_plane_vertices"]):
                valid_segments.append({
                    "index": i,
                    "vertices": segment_vertices,
                    "volume": vol
                })
                break

func _refresh_debug_visualization() -> void:
    if debug_mesh:
        debug_mesh.queue_free()
    
    var valid_indices = []
    for seg in valid_segments:
        valid_indices.append(seg["index"])
    
    debug_mesh = DebugUtil.create_debug_ring_volume_wireframe(debug_color, outer_radius, inner_radius, height, segments, valid_indices)
    add_child(debug_mesh)

func _get_segment_vertices(segment_index: int) -> Array:
    var angle1 = TAU * float(segment_index) / float(segments)
    var angle2 = TAU * float(segment_index + 1) / float(segments)
    
    # 8 vértices del segmento (cubo deformado)
    var vertices = []
    
    # Bottom inner
    vertices.append(Vector3(cos(angle1) * inner_radius, 0, sin(angle1) * inner_radius))
    vertices.append(Vector3(cos(angle2) * inner_radius, 0, sin(angle2) * inner_radius))
    
    # Bottom outer
    vertices.append(Vector3(cos(angle1) * outer_radius, 0, sin(angle1) * outer_radius))
    vertices.append(Vector3(cos(angle2) * outer_radius, 0, sin(angle2) * outer_radius))
    
    # Top inner
    vertices.append(Vector3(cos(angle1) * inner_radius, height, sin(angle1) * inner_radius))
    vertices.append(Vector3(cos(angle2) * inner_radius, height, sin(angle2) * inner_radius))
    
    # Top outer
    vertices.append(Vector3(cos(angle1) * outer_radius, height, sin(angle1) * outer_radius))
    vertices.append(Vector3(cos(angle2) * outer_radius, height, sin(angle2) * outer_radius))
    
    return vertices

func _segment_intersects_volume(segment_verts: Array, plane1_verts: Array, plane2_verts: Array) -> bool:
    # Verificar si algún vértice del segmento está dentro del volume
    for vert in segment_verts:
        var global_vert = global_transform * vert
        if _is_point_inside_lane_volume(global_vert, plane1_verts, plane2_verts):
            return true
    
    # También verificar algunos puntos en el centro del segmento
    var center = Vector3.ZERO
    for vert in segment_verts:
        center += vert
    center /= segment_verts.size()
    
    var global_center = global_transform * center
    if _is_point_inside_lane_volume(global_center, plane1_verts, plane2_verts):
        return true
    
    return false

func _get_random_valid_path():
    if valid_segments.is_empty():
        return null
    
    var fail_reasons = {
        "start_point_null": 0,
        "spawn_not_in_volume": 0,
        "projected_start_invalid": 0,
        "projected_end_invalid": 0,
        "path_invalid": 0,
        "success": 0
    }
    
    for attempt in range(max_spawn_attempts):
        # Elegir segmento válido aleatorio
        var segment = valid_segments[randi() % valid_segments.size()]
        var volume = segment["volume"]
        var start_plane_verts = volume["start_plane_vertices"]
        var end_plane_verts = volume["end_plane_vertices"]
        
        # Generar punto aleatorio en el spawn area (dentro del ring)
        var spawn_point_local = _get_random_point_in_segment(segment["index"])
        if spawn_point_local == null:
            fail_reasons["start_point_null"] += 1
            continue
        
        var spawn_position = global_transform * spawn_point_local
        
        # Verificar que el spawn point esté dentro del volumen
        if not _is_point_inside_lane_volume(spawn_position, start_plane_verts, end_plane_verts):
            fail_reasons["spawn_not_in_volume"] += 1
            if show_debug:
                _show_spawn_attempt(spawn_position, false)
            continue
        
        # Calcular la dirección del volumen (de start a end)
        var volume_direction = _get_volume_direction(start_plane_verts, end_plane_verts)
        
        # Proyectar el spawn point hacia el start plane y end plane
        var path_points = _calculate_full_path_through_volume(
            spawn_position,
            start_plane_verts,
            end_plane_verts,
            volume_direction
        )
        
        if path_points == null:
            fail_reasons["projected_start_invalid"] += 1
            if show_debug:
                _show_spawn_attempt(spawn_position, false)
            continue
        
        var start_position = path_points["start"]
        var end_position = path_points["end"]
        
        # Verificar que ambos puntos estén dentro del volumen
        if not _is_point_inside_lane_volume(start_position, start_plane_verts, end_plane_verts):
            fail_reasons["projected_start_invalid"] += 1
            if show_debug:
                _show_spawn_attempt(spawn_position, false)
            continue
        
        if not _is_point_inside_lane_volume(end_position, start_plane_verts, end_plane_verts):
            fail_reasons["projected_end_invalid"] += 1
            if show_debug:
                _show_spawn_attempt(spawn_position, false)
            continue
        
        # Verificar que el path completo sea válido
        if not _is_path_valid(start_position, end_position, start_plane_verts, end_plane_verts):
            fail_reasons["path_invalid"] += 1
            if show_debug:
                _show_spawn_attempt(spawn_position, false)
            continue
        
        # Path válido encontrado
        fail_reasons["success"] += 1
        if show_debug:
            _show_spawn_attempt(spawn_position, true)
        
        print("Spawn attempt succeeded after ", attempt + 1, " tries")
        print("Fail reasons: ", fail_reasons)
        
        return {
            "start_position": start_position,
            "end_position": end_position,
            "spawn_position": spawn_position,
            "volume": volume
        }
    
    # Si llegamos aquí, todos los intentos fallaron
    print("All ", max_spawn_attempts, " spawn attempts failed!")
    print("Fail breakdown:")
    print("  - start_point_null: ", fail_reasons["start_point_null"])
    print("  - spawn_not_in_volume: ", fail_reasons["spawn_not_in_volume"])
    print("  - projected_start_invalid: ", fail_reasons["projected_start_invalid"])
    print("  - projected_end_invalid: ", fail_reasons["projected_end_invalid"])
    print("  - path_invalid: ", fail_reasons["path_invalid"])
    
    return null

func _get_random_point_in_segment(segment_index: int):
    var angle1 = TAU * float(segment_index) / float(segments)
    var angle2 = TAU * float(segment_index + 1) / float(segments)
    
    var random_angle = randf_range(angle1, angle2)
    var random_radius = randf_range(inner_radius, outer_radius)
    var random_height = randf_range(0, height)
    
    var local_x = cos(random_angle) * random_radius
    var local_z = sin(random_angle) * random_radius
    
    return Vector3(local_x, random_height, local_z)

func _get_volume_direction(start_plane_verts: Array, end_plane_verts: Array) -> Vector3:
    # Calcular el centro de cada plano
    var start_center = Vector3.ZERO
    for v in start_plane_verts:
        start_center += v
    start_center /= start_plane_verts.size()
    
    var end_center = Vector3.ZERO
    for v in end_plane_verts:
        end_center += v
    end_center /= end_plane_verts.size()
    
    # Dirección del flujo
    return (end_center - start_center).normalized()

func _calculate_full_path_through_volume(
    spawn_point: Vector3,
    start_plane_verts: Array,
    end_plane_verts: Array,
    volume_direction: Vector3
):
    # Calcular los planos como ecuaciones
    var start_plane_normal = _get_plane_normal(start_plane_verts)
    var end_plane_normal = _get_plane_normal(end_plane_verts)
    
    # Proyectar el spawn point hacia atrás hasta el start plane
    var start_position = _intersect_ray_with_plane(
        spawn_point,
        -volume_direction,
        start_plane_verts[0],
        start_plane_normal
    )
    
    if start_position == null:
        return null
    
    # Proyectar el spawn point hacia adelante hasta el end plane
    var end_position = _intersect_ray_with_plane(
        spawn_point,
        volume_direction,
        end_plane_verts[0],
        end_plane_normal
    )
    
    if end_position == null:
        return null
    
    return {
        "start": start_position,
        "end": end_position
    }

func _get_plane_normal(plane_verts: Array) -> Vector3:
    # Usar los primeros 3 vértices para calcular la normal
    var v0 = plane_verts[0]
    var v1 = plane_verts[1]
    var v2 = plane_verts[2]
    
    var edge1 = v1 - v0
    var edge2 = v2 - v0
    
    return edge1.cross(edge2).normalized()

func _intersect_ray_with_plane(
    ray_origin: Vector3,
    ray_direction: Vector3,
    plane_point: Vector3,
    plane_normal: Vector3
):
    var denom = plane_normal.dot(ray_direction)
    
    # Rayo paralelo al plano
    if abs(denom) < 0.0001:
        return null
    
    var t = (plane_point - ray_origin).dot(plane_normal) / denom
    
    # Intersección detrás del origen
    if t < 0:
        return null
    
    return ray_origin + ray_direction * t

func _is_path_valid(start_pos: Vector3, end_pos: Vector3, start_plane_verts: Array, end_plane_verts: Array) -> bool:
    # Samplear puntos a lo largo del path y verificar que todos estén dentro del volumen
    var samples = 5
    for i in range(samples + 1):
        var t = float(i) / float(samples)
        var sample_point = start_pos.lerp(end_pos, t)
        
        if not _is_point_inside_lane_volume(sample_point, start_plane_verts, end_plane_verts):
            return false
    
    return true

func _show_spawn_attempt(position: Vector3, success: bool) -> void:
    var color = Color(0.0, 1.0, 0.0, 0.8) if success else Color(1.0, 0.0, 0.0, 0.8)
    var sphere = DebugUtil.create_debug_sphere(color, 0.005)
    world.add_child(sphere)
    sphere.global_position = position
    
    # Destruir después de 0.3 segundos
    await get_tree().create_timer(0.3).timeout
    if is_instance_valid(sphere):
        sphere.queue_free()

func _is_point_inside_lane_volume(point: Vector3, plane1_verts: Array, plane2_verts: Array) -> bool:
    if not _is_point_on_correct_side(point, plane1_verts[0], plane1_verts[1], plane1_verts[2], true):
        return false
    
    if not _is_point_on_correct_side(point, plane2_verts[3], plane2_verts[2], plane2_verts[1], true):
        return false
    
    if not _is_point_on_correct_side(point, plane1_verts[0], plane2_verts[0], plane2_verts[1], true):
        return false
    
    if not _is_point_on_correct_side(point, plane1_verts[3], plane1_verts[2], plane2_verts[2], true):
        return false
    
    if not _is_point_on_correct_side(point, plane1_verts[0], plane1_verts[3], plane2_verts[3], true):
        return false
    
    if not _is_point_on_correct_side(point, plane1_verts[1], plane2_verts[1], plane2_verts[2], true):
        return false
    
    return true

func _is_point_on_correct_side(point: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, inside: bool) -> bool:
    var normal = (v2 - v1).cross(v3 - v1).normalized()
    var to_point = point - v1
    var dot = normal.dot(to_point)
    
    return dot >= 0 if inside else dot <= 0
