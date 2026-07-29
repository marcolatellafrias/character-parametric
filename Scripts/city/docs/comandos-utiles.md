Comandos útiles


PROBAR MULTIPLAYER LOCAL (vos solo, sin Steam ni amigo)

Usa ENet en localhost (127.0.0.1). Dos opciones:

Opción A - desde el editor:
1. Debug -> Run Multiple Instances -> Run 2 Instances.
2. En una instancia clic "Host local" (menú principal); en la otra "Join local".

Opción B - por consola (tecla a la izquierda del 1):
  host_local          (en una instancia)
  join_local          (en la otra, default 127.0.0.1)

Los dos personajes se ven distintos (seed = peer id) y se sincroniza todo (cápsula, cajas, agarre).


PUBLICAR LA BUILD A GITHUB

Sube la carpeta C:\ejecutables neuvos aires a un único Release (tag dev), pisando el mismo zip cada vez.

Una sola vez (instalar, loguear, y crear el release vacío). Copiá y pegá:

winget install --id GitHub.cli

gh auth login

gh release create dev --title "Playtest build" --notes "build para testear"


Cada vez que quieras publicar. Copiá y pegá estas dos líneas:

Compress-Archive -Path "C:\ejecutables neuvos aires\*" -DestinationPath "$env:TEMP\nuevos-build.zip" -Force

gh release upload dev "$env:TEMP\nuevos-build.zip" --clobber


Link para tu amigo (siempre el mismo):

https://github.com/marcolatellafrias/character-parametric/releases/download/dev/nuevos-build.zip
