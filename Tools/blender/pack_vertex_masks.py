# EMPAQUETA LAS CAPAS DE MÁSCARA EN UNA SOLA, PARA EXPORTAR.
#
# Se corre desde el Text Editor de Blender (botón ▶ Run Script) antes de exportar el .glb.
#
# ── POR QUÉ EXISTE ────────────────────────────────────────────────────────────────────────────────
# En Blender conviene pintar UNA CAPA POR EFECTO, en blanco y negro: son independientes, el pincel no
# pisa nada, y ves el valor exacto que estás poniendo.
#
# Pero Godot tiene UNA SOLA ranura de color por malla (`ARRAY_COLOR`). Medido sobre este proyecto: el
# .glb llega a exportar COLOR_0 y COLOR_1, y el importador se queda solo con el primero. Las ranuras
# CUSTOM0..3 existen y el importador de glTF nunca las llena.
#
# O sea que en algún punto hay que juntar. Este script lo hace al final, sin tocar cómo pintás: lee el
# gris de cada capa y lo mete en un canal distinto de una capa combinada.
#
#   capa 1 → R      capa 3 → B
#   capa 2 → G      capa 4 → A
#
# ── LO QUE HAY QUE HACER EN BLENDER ───────────────────────────────────────────────────────────────
# 1. Pintá las capas con los nombres de MESH_MASKS y color base **negro**. Negro = máscara en cero,
#    que es el neutro; pintás con blanco y los grises son valores intermedios.
#    El DOMINIO da igual —Vertex o Face Corner— porque el script normaliza a Corner, que es el más
#    general: ahí un vértice puede tener valores distintos por cara y una costura puede tener borde duro.
# 2. Corré este script (Alt+P). Empaqueta Y exporta el .glb — no hay que exportar aparte.
#
# Cada vez que pintes hay que volver a correrlo: lee el estado de las capas en ese momento, no es
# automatico. Y guardá el .blend por tu cuenta, que el script no lo hace.
#
# Es no destructivo: las capas de trabajo quedan intactas y se puede volver a correr cuantas veces
# haga falta.
#
# ── SOBRE EL VALOR QUE LLEGA ──────────────────────────────────────────────────────────────────────
# El script copia los números tal como están, sin convertir. Está medido que lo que se pinta como hex
# `808080` llega al shader como **0.216**, no como 0.5: Blender guarda el color en lineal y el hex que
# tipeás es sRGB. La corrección se hace UNA vez, en el shader (`linear_to_srgb` al leer la máscara).
# Compensar acá además sería corregir dos veces.

import bpy

# Malla → qué capa va a cada canal, en orden R, G, B, A.
#
# Cadena vacía = ese canal queda en cero. Una capa que no exista también queda en cero y avisa, así
# que se puede ir pintando de a una sin que el script falle.
MESH_MASKS = {
    # Ropa
    "body_mesh":   ["mask_shadow_grad", "mask_shadow_paint", "mask_stain", "mask_fade"],
    "arms_mesh":   ["mask_shadow_grad", "mask_shadow_paint", "mask_stain", "mask_fade"],
    "shirt_mesh":  ["mask_shadow_grad", "mask_shadow_paint", "mask_stain", "mask_fade"],
    # Piel
    "head_mesh":   ["mask_shadow_grad", "mask_shadow_paint", "mask_flush", ""],
    "neck_mesh":   ["mask_shadow_grad", "mask_shadow_paint", "mask_flush", ""],
    "hands_mesh":  ["mask_shadow_grad", "mask_shadow_paint", "mask_flush", ""],
    "wrist_mesh":  ["mask_shadow_grad", "mask_shadow_paint", "mask_flush", ""],
    # Pelo y zapatos: solo sombra
    "hair_mesh2":  ["mask_shadow_grad", "mask_shadow_paint", "", ""],
    "shoes_mesh":  ["mask_shadow_grad", "mask_shadow_paint", "", ""],
}

# Nombre de la capa combinada. Es la que hay que dejar ACTIVA al exportar.
OUTPUT = "masks"

# Si es True, además de empaquetar EXPORTA el .glb. Así el flujo es un solo botón: Alt+P y listo.
#
# Las opciones de abajo están verificadas contra un export hecho a mano desde la interfaz: mismo
# número de mallas, mismos vértices y mismas shape keys. Si algún día cambiás algo en el diálogo de
# export, cambialo también acá o el script te lo va a pisar.
EXPORTAR = True
GLB_PATH = r"d:\Godot\character-parametric\Models\character.glb"


def read_layer(mesh, name):
    """El gris de una capa, UN VALOR POR CORNER. Devuelve None si la capa no existe.

    Se normaliza todo a CORNER porque es el dominio más general: Blender crea las capas de color en
    Face Corner por defecto, y ahí un vértice puede tener valores distintos según la cara — que es
    justo lo que permite un borde duro en una costura. Leyendo en POINT eso se perdería.

    Una capa que esté en POINT se expande: todos los corners de un vértice comparten su valor.
    """
    if not name:
        return None
    attr = mesh.color_attributes.get(name)
    if attr is None:
        return None
    out = [0.0] * len(mesh.loops)
    # Se lee el canal R: las capas se pintan en gris, o sea R = G = B.
    if attr.domain == 'CORNER':
        for i, d in enumerate(attr.data):
            out[i] = d.color[0]
    else:
        por_vertice = [d.color[0] for d in attr.data]
        for i, lp in enumerate(mesh.loops):
            out[i] = por_vertice[lp.vertex_index]
    return out


def pack(obj):
    mesh = obj.data
    layers = MESH_MASKS[obj.name]
    n = len(mesh.loops)
    print("· %s (%d verts, %d corners)" % (obj.name, len(mesh.vertices), n))

    channels = []
    for ch, name in zip("RGBA", layers):
        vals = read_layer(mesh, name)
        if name and vals is None:
            print("  %s ← '%s' NO EXISTE, queda en cero" % (ch, name))
        elif name:
            pintados = sum(1 for v in vals if v > 0.002)
            print("  %s ← %s   (%d/%d corners pintados)" % (ch, name, pintados, n))
            # ⚠ EL CANAL A ARRANCA EN 1, NO EN 0, cuando no tiene capa.
        #
        # En glTF el alpha del color de vertice es OPACIDAD, y un material que lo lea con alpha 0 se
        # dibuja transparente o negro. Los otros tres canales en cero son inofensivos porque nadie los
        # interpreta como color; el alpha si.
        neutro = 1.0 if ch == "A" else 0.0
        channels.append(vals if vals is not None else [neutro] * n)

    # La combinada se recrea siempre: así reflejar un cambio en las capas es volver a correr esto, y
    # no queda estado viejo si se reordenan los canales.
    old = mesh.color_attributes.get(OUTPUT)
    if old is not None:
        mesh.color_attributes.remove(old)
    attr = mesh.color_attributes.new(name=OUTPUT, type='FLOAT_COLOR', domain='CORNER')

    r, g, b, a = channels
    for i, d in enumerate(attr.data):
        d.color = (r[i], g[i], b[i], a[i])

    # ⚠ HAY DOS PUNTEROS Y HAY QUE SETEAR LOS DOS.
    #
    # `active_color_index` es el de EDICIÓN (el que se pinta) y `render_color_index` es el de RENDER —
    # y el exportador de glTF con "Vertex Colors: Active" usa el **de render**. Seteando solo el activo,
    # el empaquetado se hacía bien pero se exportaba otra capa, y en el juego se veían todos los canales
    # iguales porque la que viajaba era una capa gris.
    idx = mesh.color_attributes.find(OUTPUT)
    mesh.color_attributes.active_color_index = idx
    mesh.color_attributes.render_color_index = idx
    mesh.attributes.active_index = mesh.attributes.find(OUTPUT)
    print("  → '%s' escrita, activa y de render" % OUTPUT)


def exportar():
    """Exporta el .glb con las mismas opciones que el export manual.

    `export_vertex_color='ACTIVE'` + `export_all_vertex_colors=False` es lo que hace viajar SOLO la capa
    combinada. Sin el segundo, Blender manda todas las capas como COLOR_0, COLOR_1… y Godot se queda con
    la primera nomás — que puede no ser la que querés.
    """
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format='GLB',
        export_apply=False,          # los modificadores Armature NO se aplican
        export_skins=True,
        export_morph=True,           # shape keys
        export_morph_normal=True,    # y sus normales, o el sombreado no las sigue
        export_morph_tangent=False,
        export_cameras=False,
        export_lights=False,
        export_vertex_color='ACTIVE',
        export_all_vertex_colors=False,
    )
    print("[pack_vertex_masks] exportado a %s" % GLB_PATH)


def main():
    hechas = 0
    for name in MESH_MASKS:
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != 'MESH':
            print("· %s: no está en la escena, se saltea" % name)
            continue
        pack(obj)
        hechas += 1
    print("\n[pack_vertex_masks] %d mallas empaquetadas." % hechas)
    if EXPORTAR:
        exportar()


main()
