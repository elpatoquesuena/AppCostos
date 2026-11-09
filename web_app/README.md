# AppCostos Web — edición controlada

Cliente web conectado al mismo proyecto Firebase que Android.

## Estado de esta etapa
- Inicio de sesión con Firebase Authentication (correo y contraseña).
- Lectura de la copia manual `users/{uid}/appData/current` y de los registros sincronizados en `users/{uid}/records`.
- La vista prioriza los registros individuales cuando una tabla ya tiene registros publicados; usa la copia manual como respaldo por tabla.
- Alta y edición de insumos.
- Alta y edición de datos generales de recetas.
- Los cambios de precio de insumos generan un registro en `ingredient_prices` automáticamente.
- Los cambios del precio de venta de recetas generan un registro en `recipe_prices` automáticamente.
- Escrituras con el mismo formato de documentos, identificadores y versiones que consume la sincronización de Android.
- Control optimista de versión para evitar sobrescribir un registro que cambió desde otro dispositivo.

## Alcance todavía no habilitado
- Eliminación de registros.
- Edición de ingredientes y cantidades dentro de cada receta (`recipe_items`).
- Edición manual de los historiales de precios.
- Edición de parámetros (`settings`).

Estas operaciones requieren manejar relaciones y eliminaciones dependientes; se habilitarán después de validar esta primera etapa.

## Modelo de escritura
Cada registro se guarda en `users/{uid}/records/{table}__{syncId}` con:
- `table`, `syncId`, `version`, `deleted`, `payload`, `updatedAt`.

Para registros nuevos, la web genera un `syncId` y comienza en versión 1. Las referencias de los historiales usan `ingredient_sync_id` y `recipe_sync_id`, que Android resuelve a sus IDs locales al sincronizar.

## Pruebas recomendadas
1. Iniciar sesión con la misma cuenta utilizada en Android.
2. Crear un insumo de prueba con cantidad, unidad y precio.
3. Comprobar que aparezca en Firestore como `ingredients__{syncId}` y que se genere su registro `ingredient_prices__{syncId}`.
4. Ejecutar la sincronización desde Android y confirmar que el insumo y su historial aparezcan correctamente.
5. Editar el insumo desde la web y comprobar que Android reciba la modificación.
6. Repetir con una receta, verificando `recipes` y `recipe_prices`.
7. Editar el mismo registro desde dos dispositivos de forma consecutiva y confirmar que la web detecte la versión desactualizada en vez de sobrescribir el cambio.

## Firebase y seguridad
- Se usa el proyecto `baseappcostos` y la app Web registrada para ese proyecto.
- Authentication debe tener habilitado Email/Password.
- Las reglas actuales limitan lectura y escritura al UID autenticado. No hace falta abrir el acceso globalmente.
- Servir mediante HTTPS o servidor local; no abrir `index.html` como archivo local.

## Publicación
El sitio se publica con GitHub Actions. En el repositorio, **Settings → Pages → Build and deployment → Source** debe estar seleccionado **GitHub Actions**.
