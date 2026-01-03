extends Node3D
class_name AreaInstantiator

@export var outer_radius: float = 4.0
@export var inner_radius: float = 1.5
@export var height: float = 2.0
@export var segments: int = 16
@export var debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
@export var show_debug: bool = true

@export var world: Node3D
@export var spawn_interval: float = 3.0
@export var max_spawn_attempts: int = 50

@export_group("Car Size Ranges")
@export var debug_size_factor: float = 0.1
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
    car.global_position = spawn_data["start_position"]
    
    # Orientar el auto hacia el end_position
    var direction = (spawn_data["end_position"] - spawn_data["start_position"]).normalized()
    if direction.length() > 0.001:
        car.look_at(spawn_data["end_position"], Vector3.UP)
    
    # Configurar el path en el auto
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
        "start_not_in_volume": 0,
        "end_not_in_volume": 0,
        "path_invalid": 0,
        "success": 0
    }
    
    for attempt in range(max_spawn_attempts):
        # Elegir segmento válido aleatorio
        var segment = valid_segments[randi() % valid_segments.size()]
        var volume = segment["volume"]
        var start_plane_verts = volume["start_plane_vertices"]
        var end_plane_verts = volume["end_plane_vertices"]
        
        # Generar punto en el start_plane dentro del área de spawn
        var start_point_local = _get_random_point_in_segment(segment["index"])
        if start_point_local == null:
            fail_reasons["start_point_null"] += 1
            continue
        
        var start_position = global_transform * start_point_local
        
        # Verificar que el punto esté en el start_plane del volumen
        if not _is_point_inside_lane_volume(start_position, start_plane_verts, end_plane_verts):
            fail_reasons["start_not_in_volume"] += 1
            if show_debug:
                _show_spawn_attempt(start_position, false)
            continue
        
        # Proyectar el punto al end_plane manteniendo posición relativa
        var end_position = _project_point_to_end_plane(start_position, start_plane_verts, end_plane_verts)
        
        # Verificar que el end_position también esté dentro del volumen
        if not _is_point_inside_lane_volume(end_position, start_plane_verts, end_plane_verts):
            fail_reasons["end_not_in_volume"] += 1
            if show_debug:
                _show_spawn_attempt(start_position, false)
            continue
        
        # Verificar que el path completo sea válido (sin clipping)
        if not _is_path_valid(start_position, end_position, start_plane_verts, end_plane_verts):
            fail_reasons["path_invalid"] += 1
            if show_debug:
                _show_spawn_attempt(start_position, false)
            continue
        
        # Path válido encontrado
        fail_reasons["success"] += 1
        if show_debug:
            _show_spawn_attempt(start_position, true)
        
        print("Spawn attempt succeeded after ", attempt + 1, " tries")
        print("Fail reasons: ", fail_reasons)
        
        return {
            "start_position": start_position,
            "end_position": end_position,
            "volume": volume
        }
    
    # Si llegamos aquí, todos los intentos fallaron
    print("All ", max_spawn_attempts, " spawn attempts failed!")
    print("Fail breakdown:")
    print("  - start_point_null: ", fail_reasons["start_point_null"])
    print("  - start_not_in_volume: ", fail_reasons["start_not_in_volume"])
    print("  - end_not_in_volume: ", fail_reasons["end_not_in_volume"])
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

func _project_point_to_end_plane(point: Vector3, start_plane_verts: Array, end_plane_verts: Array) -> Vector3:
    # Los vértices están ordenados como: [v1_base, v2_base, v3_top, v4_top]
    # Formar un quad con estos 4 puntos
    var v0 = start_plane_verts[0]  # base izquierda
    var v1 = start_plane_verts[1]  # base derecha
    var v2 = start_plane_verts[2]  # top derecha
    var v3 = start_plane_verts[3]  # top izquierda
    
    # Proyectar el punto al plano del start_plane
    var plane_normal = (v1 - v0).cross(v3 - v0).normalized()
    var point_to_plane = point - v0
    var projected_point = point - plane_normal * point_to_plane.dot(plane_normal)
    
    # Encontrar coordenadas paramétricas (u, v) en el quad
    # u va de v0 a v1 (eje base)
    # v va de v0 a v3 (eje lateral)
    var base_vec = v1 - v0
    var side_vec = v3 - v0
    var point_vec = projected_point - v0
    
    # Resolver para u y v (aproximación simple)
    var u = 0.5
    var v = 0.5
    
    if base_vec.length_squared() > 0.0001:
        u = point_vec.dot(base_vec) / base_vec.length_squared()
    
    if side_vec.length_squared() > 0.0001:
        v = point_vec.dot(side_vec) / side_vec.length_squared()
    
    # Clampar u y v para mantenerlos en el quad
    u = clamp(u, 0.0, 1.0)
    v = clamp(v, 0.0, 1.0)
    
    # Aplicar interpolación bilineal en el end_plane
    var end_v0 = end_plane_verts[0]
    var end_v1 = end_plane_verts[1]
    var end_v2 = end_plane_verts[2]
    var end_v3 = end_plane_verts[3]
    
    # Interpolación bilineal: 
    # bottom = lerp(v0, v1, u)
    # top = lerp(v3, v2, u)
    # result = lerp(bottom, top, v)
    var bottom = end_v0.lerp(end_v1, u)
    var top = end_v3.lerp(end_v2, u)
    var result = bottom.lerp(top, v)
    
    return result

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
    var sphere = DebugUtil.create_debug_sphere(color, 1.0)
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
