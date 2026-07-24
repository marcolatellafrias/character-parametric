Comandos útiles

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
