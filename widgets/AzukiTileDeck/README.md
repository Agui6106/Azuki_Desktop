# Azuki Tile Deck — v0.5b

Migración del prototipo v0.4 al modelo persistente. Esta entrega fue preparada a partir de los tres archivos QML proporcionados por el usuario. No es una instalación completa independiente: se aplica sobre el paquete que ya funciona en su equipo.

## Alcance

Se conserva el aspecto de los componentes originales, incluyendo la superficie, el encabezado, el tamaño de referencia 1392 × 464, las unidades 156 × 136, la separación de 16 px, la InfoBar de 78 px, sus fuentes y el icono `window-new`. No se fija el tamaño exterior del plasmoide: Plasma sigue controlando la geometría elegida por el usuario.

Los seis mosaicos se generan ahora desde datos. El modelo contiene nombres completos y etiquetas independientes, IDs estables, tipos, tamaños, descripciones, lanzamiento tipado, metadata y referencias futuras a artwork. Los seis registros conservan los textos, IDs y comandos del código recibido. Desarrollo continúa siendo un acceso de aplicación sin comando; todavía no se implementan las carpetas.

El empaquetador provisional dispone de dos filas y bloques de cuatro columnas. La composición de seis elementos se mantiene. Los elementos adicionales pueden ocupar nuevos bloques hacia la derecha, con desplazamiento horizontal. En v0.5c se añadirá el editor de Preferencias. Las páginas/grupos completos, imágenes, RAWG y carpetas pertenecen a fases posteriores.

## Instalación conservadora

Requisitos: Ubuntu con la misma sesión Plasma 6 del proyecto, Python 3 y `kpackagetool6`. No requiere sudo, pip, npm ni instalar paquetes adicionales. El script no ejecuta ningún juego ni acción de energía.

1. Extrae el ZIP en una carpeta de trabajo, por ejemplo `~/Documentos/AzukiTileDeck_v0.5b`.
2. Abre una terminal en la carpeta extraída y ejecuta la vista previa:

   ```bash
   python3 install.py
   ```

3. Si la ruta e ID son correctos, aplica la actualización:

   ```bash
   python3 install.py --apply
   ```

   El instalador crea primero un respaldo completo con un nombre del tipo `AzukiTileDeck_pre_v0.5b_YYYYMMDD_HHMMSS`, junto al proyecto. No sobrescribe el respaldo v0.4 que ya creaste. Conserva el `metadata.json` original, salvo el número de versión, y los archivos ajenos a esta actualización. Si existe `main.xml`, añade únicamente `libraryJson` sin eliminar las demás entradas. La configuración personal almacenada por Plasma no se borra ni se modifica directamente.

4. Recarga Plasma desde una terminal:

   ```bash
   kquitapp6 plasmashell
   plasmashell --replace &
   ```

   No elimines el widget del escritorio ni borres los archivos de configuración. La instancia existente debe conservar la geometría que ajustaste manualmente.

Para utilizar otra ubicación de proyecto: `python3 install.py --package /ruta/al/paquete --apply`. Para preparar solamente los archivos sin ejecutar kpackagetool6, añade `--no-upgrade`.

## Prueba de aceptación

Comprueba que aparecen los seis mosaicos en el mismo orden y con sus mismas dimensiones. Selecciona VS Code y verifica que InfoBar muestra el nombre completo, Microsoft, Desarrollo, Code Editor y el icono `window-new`. Prueba ABRIR y luego una única prueba JUGAR con Mini Metro u otro juego que prefieras. Comprueba que solo seleccionar el mosaico no ejecuta nada. Desarrollo debe permanecer deshabilitado.

Esta etapa no incorpora todavía un editor. Es normal que no aparezca una nueva pestaña de Preferencias: se implementará en v0.5c, utilizando exactamente el campo `libraryJson` creado aquí.

## Archivos

```text
overlay/
└── contents/
    ├── ui/
    │   ├── main.qml             Coordinador y estado seleccionado
    │   ├── AzukiTile.qml        Componente visual existente, adaptado
    │   ├── InfoBar.qml          Archivo original sin modificaciones
    │   ├── TileGrid.qml         Posicionamiento y desplazamiento horizontal
    │   ├── TileModel.js         Validación, normalización y lógica del modelo
    │   └── TileDefaults.js      Copia inicial generada desde el JSON
    ├── data/
    │   └── default-library.json
    └── config/
        └── main.xml             Entrada KConfigXT libraryJson
```

`default-library.json` es la copia inicial de referencia. `TileDefaults.js` se genera a partir de ella para disponer de una copia local sin peticiones HTTP ni lectura síncrona mediante XMLHttpRequest. `main.xml` contiene el mismo JSON como valor predeterminado de la configuración. Una vez que existan datos guardados desde Preferencias, esos datos tendrán prioridad; una actualización del paquete no debe sobrescribirlos.

El modelo utiliza `schemaVersion: 1`. Un esquema desconocido, IDs duplicados, tamaños no admitidos o lanzamientos inválidos se rechazan sin reemplazar el último modelo válido en memoria. Los IDs de juego de Steam se almacenan como cadenas de dígitos. Los comandos ejecutables son definidos por el usuario; la futura importación de RAWG no debe ejecutar comandos recibidos de un proveedor externo.

## Recuperación

Si la carga visual falla, no es necesario borrar la instancia ni perder su posición. Usa el respaldo que ya tenías o el que imprime el instalador. El respaldo automático contiene el paquete directamente (metadata.json y contents), por lo que puedes restaurar la versión instalada con:

```bash
kpackagetool6 --type Plasma/Applet --upgrade "/ruta/exacta/al/respaldo"
kquitapp6 plasmashell
plasmashell --replace &
```

Si utilizas tu respaldo anterior cuyo contenido tiene una subcarpeta `package`, apunta a esa subcarpeta. Conserva el respaldo hasta validar completamente la nueva versión. El instalador no elimina archivos de usuario ni toca `plasma-org.kde.plasma.desktop-appletsrc`.

Si necesitas restaurar también el árbol de trabajo, copia el respaldo a una carpeta nueva y trabaja desde ella; no sobrescribas a ciegas el proyecto actual. Esto permite comparar ambas versiones antes de reemplazar ningún archivo.

## Validación realizada y límites

Se ejecutaron las pruebas del modelo mediante Node.js, incluyendo los seis registros, posiciones, normalización, lanzamiento, errores y 101 escenarios de empaquetado. El instalador se probó contra un paquete ficticio, preservando otras configuraciones y archivos, generando respaldo y rechazando IDs incorrectos. El JSON y XML se validaron estructuralmente. No se ejecutó Plasma ni qmllint en el entorno de creación, porque las bibliotecas KDE/Qt no están instaladas aquí. La aceptación visual y los lanzamientos deben comprobarse en la sesión real del usuario.

Referencias de implementación: documentación oficial de Qt sobre recursos JavaScript y Repeater, y documentación KDE sobre configuración de widgets Plasma.
