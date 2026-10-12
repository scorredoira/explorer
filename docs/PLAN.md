# Explorer

Explorador de archivos propio para macOS, para usar en lugar de Finder.

## Tecnología

- App nativa en Swift + AppKit, Swift Package Manager, sin Xcode project.
- `./build.sh` genera `build/Explorer.app` firmada con el certificado Apple Development (firma estable: macOS no vuelve a pedir permisos de Escritorio/Documentos en cada build).
- `./install.sh` la copia a `~/Applications` y la abre.
- No sustituye a Finder como app por defecto.

## Ventana

- Sin pestañas. Varias ventanas: `cmd+n` abre otra en la misma carpeta.
- Al abrir la app: una ventana en la carpeta de inicio (por defecto el home; configurable en Ajustes). No recuerda ventanas.
- Aspecto Finder: barra lateral translúcida a la izquierda con Favoritos (se oculta con su botón); en la barra de la ventana atrás, adelante, subir, la ruta completa editable y el filtro.
- A la derecha de la barra lateral, la lista.

## Lista

- Siempre en modo lista. Columnas: Nombre, Fecha de modificación, Tamaño, Tipo.
- Clic en la cabecera ordena; las carpetas siempre arriba.
- El triángulo despliega la carpeta en el árbol; doble clic entra en ella. Doble clic en un archivo lo abre.
- Tamaño de carpeta recursivo en la columna Tamaño: se calcula en segundo plano (muestra "…" mientras tanto), se cancela al cambiar de carpeta y se guarda en caché. Si algo cambia dentro, el valor viejo se queda hasta que se vuelve a pintar la fila (como mucho uno cada 30 s por carpeta).
- La lista se actualiza sola cuando cambian los archivos (FSEvents).
- Los elementos cortados se ven atenuados.

## Ruta

- Muestra la ruta completa y se puede editar. Enter va a la carpeta; si es un archivo, va a su carpeta y lo selecciona. `~` vale.
- Tab autocompleta como en la terminal.
- `cmd+l` o `cmd+shift+g` ponen el foco en la ruta. Esc vuelve a la lista.

## Filtro

- Filtra por nombre en la carpeta actual, mientras escribes (`cmd+f`). Flecha abajo pasa a la lista.

## Favoritos (barra lateral izquierda)

- Solo carpetas.
- Arrastrar una carpeta entre dos favoritos la añade ahí. Arrastrar dentro del panel los reordena.
- Arrastrar archivos encima de un favorito los mueve a esa carpeta (con option, los copia).
- Botón derecho: Abrir, Abrir en nueva ventana, Copiar ruta, Abrir terminal aquí, Quitar de Favoritos.
- Por defecto: home, Escritorio, Documentos, Descargas.

## Botón derecho

Sobre un elemento:

- Abrir / Abrir en nueva ventana (carpetas).
- Abrir con ▸ (programas que pueden abrirlo) y Abrir siempre .ext con ▸ (lo recuerda la app, sin tocar Finder).
- Vista rápida.
- Copiar ruta (siempre). Mostrar en Finder.
- Cortar, Copiar, Pegar.
- Renombrar, Mover a la Papelera.
- Nueva carpeta / Nuevo archivo: dentro del elemento si es carpeta; en su carpeta si es archivo.
- Abrir terminal aquí. Añadir a Favoritos (carpetas).
- Mostrar/Ocultar archivos ocultos.

Sobre zona blanca (la carpeta que estás viendo): Nueva carpeta, Nuevo archivo, Pegar, Copiar ruta, Abrir terminal aquí, Añadir a Favoritos, Mostrar/Ocultar archivos ocultos.

## Arrastrar, cortar, copiar y pegar

- Arrastrar entre ventanas y desde/hacia otras apps (Finder, escritorio, Mail).
- Al arrastrar: mismo disco = mover; otro disco = copiar; con option = copiar.
- `cmd+c` / `cmd+x` / `cmd+v` como en Windows/Linux: cortar + pegar mueve. Pegar va a la carpeta actual (o a la carpeta del botón derecho).
- Copiar archivos desde Finder y pegar aquí funciona, y al revés.
- Si el nombre existe: "nombre 2". Copiar en la misma carpeta: "nombre copia".

## Terminal

- Abrir terminal aquí abre Ghostty en esa carpeta. Se puede cambiar en Ajustes.

## Atajos

| Atajo | Acción |
|---|---|
| `cmd+n` | Nueva ventana (misma carpeta) |
| `cmd+shift+n` | Nueva carpeta |
| `cmd+option+n` | Nuevo archivo |
| `cmd+[` / `cmd+]` | Atrás / Adelante |
| `cmd+↑` | Carpeta superior |
| `cmd+↓` | Abrir |
| Enter | Renombrar |
| Espacio / `cmd+y` | Vista rápida |
| `cmd+backspace` | Mover a la Papelera |
| `cmd+option+c` | Copiar ruta |
| `cmd+option+t` | Abrir terminal aquí |
| `cmd+shift+.` | Mostrar/ocultar archivos ocultos |
| `cmd+f` | Filtro |
| `cmd+l`, `cmd+shift+g` | Editar ruta |
| `cmd+,` | Ajustes |

## Ajustes

- Carpeta de inicio.
- Terminal.
- Mostrar archivos ocultos.
- Lista de "Abrir siempre con" por extensión, con opción de quitar.

## Pendiente (después)

- Deshacer (`cmd+z`) de mover/renombrar/papelera.
- Icono de la app.
- Progreso visible en copias grandes.
