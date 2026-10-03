# ChoskyCare

Para mirar qué narices está ocupando el disco del Mac y decidir qué merece ir a la Papelera. ChoskyCare junta dos partes en una app nativa:

- **Storage Care**: ver qué ocupa espacio antes de borrar a lo loco.
- **Software Care**: revisar apps, cachés y restos sabiendo qué estás tocando.

Primero miras, luego decides. Que una carpeta pese mucho no significa que sobre.

## La idea detrás de esto

- Nada se borra automáticamente.
- Todo se procesa localmente.
- Los elementos se envían a la Papelera cuando es posible.
- Cada limpieza explica qué es, cuánto ocupa y qué puede ocurrir.
- Sin “RAM booster”, porcentajes inventados, telemetría ni servidores.

## Qué trae ahora mismo

### Storage Care
- Escaneo asíncrono de tu carpeta de usuario o de cualquier carpeta, con progreso y cancelación (⌘R / ⌘.).
- Incluye archivos ocultos y `~/Library` (configurable en Ajustes).
- Los paquetes (apps, fototecas de Fotos, `.xcarchive`…) cuentan con su tamaño real y se tratan como un solo elemento.
- Mapa *treemap* squarified con el total completo (agrupa el resto en «Otros»). Clic en una carpeta para entrar; botón «Carpeta superior» para subir.
- Archivos grandes con umbral configurable, tabla ordenable, Vista rápida (espacio / doble clic) y menú contextual.
- Descargas olvidadas según la fecha en que llegaron a Descargas.
- Envío seguro a la Papelera; las listas se actualizan al momento.

### Software Care
- Inventario de `/Applications`, `~/Applications` y sus subcarpetas (p. ej. `Utilities`).
- Tamaño real, versión, bundle ID y **fecha de última apertura** (las apps sin abrir en 6 meses se marcan).
- Búsqueda y ordenación por cualquier columna.
- Desinstalación asistida: los restos se atribuyen al bundle ID más específico (los datos de una beta no se asignan a la versión estable) y puedes desmarcar cada uno antes de confirmar.
- No permite desinstalar apps abiertas ni la propia ChoskyCare.
- Si hay dos copias de la misma app, no ofrece sus restos (los ajustes son compartidos).

### Limpieza segura
- Cachés, registros, DerivedData, cachés del Simulador, Archives, iOS DeviceSupport, Homebrew y npm.
- Se mueve el **contenido** de cada carpeta, nunca la carpeta en sí; las carpetas anidadas (Homebrew dentro de Caches) no se cuentan dos veces.
- La Papelera se muestra solo como información: vaciarla es decisión tuya, desde Finder.

## Cómo arrancarlo

```bash
swift run
```

Para generar una app `.app` firmada ad hoc en `dist/`:

```bash
./scripts/build-app.sh
```

Pruebas:

```bash
swift test
```

Pruebas de humo de solo lectura contra tu propio Mac (apps, cachés y Descargas reales; no mueven nada):

```bash
CHOSKY_LIVE=1 swift test --filter LiveSmokeTests
```

También puedes abrir `Package.swift` con Xcode y ejecutar el esquema `ChoskyCare` en **My Mac**.

Requiere macOS 14 o posterior y Xcode con Swift 6.

## Seguridad

- Solo se pueden mover elementos dentro de tu carpeta de usuario o de `/Applications`, comparando rutas por componentes (`/Users/ana` no autoriza `/Users/anabel`).
- Nunca se mueven tu carpeta de usuario, `~/Library`, `Documentos`, `Descargas`, `Caches`, `Containers`, etc. como un todo, ni nada que ya esté en la Papelera.
- Cada acción pide confirmación con el número de elementos y el tamaño, y muestra después qué se movió y qué falló.
- Para escanear carpetas protegidas, macOS puede requerir **Acceso total al disco** (hay un acceso directo en Ajustes).

## Estado

La base funciona y se puede seguir ampliando. Para distribuirla públicamente todavía falta:
- añadir icono y firma con Developer ID;
- probar APFS, clones y hard links en hardware real;
- revisar las reglas de limpieza;
- añadir notarización y política de privacidad.
