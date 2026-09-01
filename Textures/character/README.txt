Texturas de los planos de feature del personaje.

El nombre del archivo es el NOMBRE DE LA MALLA en el .glb, con extension .png:

  forehead_plane_mesh.png
  brows_plane_mesh.png
  eyes_plane_mesh.png
  mouth_plane_mesh.png

Se cargan por convencion (CharacterAppearance._source_texture), asi que alcanza con dejar
el archivo aca: no hay nada que registrar ni que re-exportar del lado de Blender.

Se exportan en BLANCO o escala de grises sobre transparente cuando el plano se tine con un
color del seed (cejas, pelos, arrugas). El tinte multiplica, y negro por cualquier cosa
sigue siendo negro.
