# vendor — binarios fijados para instalaciones reproducibles

Aquí se guardan los binarios que el instalador necesita y cuyo origen
externo puede dejar de ofrecer una versión concreta. El instalador los
verifica con SHA-256 antes de usarlos.

## ueberzugpp

- Archivo: `ueberzugpp_2.9.11_amd64.deb`
- Versión: `2.9.11`
- SHA-256: `7f351202756f5027ddf752da9d90bc67f0be41d8338f5b851b828d4386a5e815`
- Origen: build Debian 13 de OBS, repo `home:justkidding`
  (`https://download.opensuse.org/repositories/home:/justkidding/Debian_13/amd64/`).
- Licencia y fuente: ver `NOTICE`.

### Por qué está aquí

La versión anterior (`2.9.10`) desapareció del OBS y el instalador fallaba
con un 404 en la verificación final. Guardar el `.deb` en el repo hace que
`sudo ./install.sh` no dependa de que OBS conserve esa versión.

El instalador instala este `.deb` local con `apt-get install`, que resuelve
sus dependencias (libvips/OpenCV/GDAL) y configura el paquete en una sola
transacción. `dpkg -i` + `apt-get -f` queda solo como fallback. No se añade
el repositorio OBS a APT.

### Actualizar la versión vendorizada

1. Descargar el `.deb` nuevo del OBS:

   ```sh
   cd vendor
   curl -fsSLO https://download.opensuse.org/repositories/home:/justkidding/Debian_13/amd64/ueberzugpp_<VERSION>_amd64.deb
   sha256sum ueberzugpp_<VERSION>_amd64.deb
   ```

2. Actualizar en `lib/previews.sh`:

   ```sh
   UEBERZUGPP_VERSION="<VERSION>"
   UEBERZUGPP_SHA256="<SHA-256>"
   ```

3. Actualizar la versión/SHA en este README y en `NOTICE` si cambia la
   licencia.

4. Borrar el `.deb` anterior y hacer commit de `vendor/` y
   `lib/previews.sh`.

Las máquinas ya instaladas **no se degradan**: `install_previews` respeta
cualquier versión instalada igual o más nueva que la fijada. Para
actualizar una máquina sin tocar el repo:

```sh
ytwatch-update --ueberzugpp
```
