# AppCostos Web — fase de auditoría (solo lectura)

Esta carpeta inicia el cliente web de AppCostos. Esta fase NO modifica ni crea documentos en Firestore.

## Estado
- Login con Firebase Authentication (correo y contraseña).
- Lectura de la copia manual existente en `users/{uid}/appData/current`.
- Lectura y conteo de registros individuales en `users/{uid}/records`.
- Comparación de cantidades por tabla para detectar si los registros individuales están incompletos.
- Vista de insumos y recetas de la copia manual, sin botones de edición.

## Antes de probar
1. En Firebase Console, proyecto `costeappbase`, registrar una aplicación Web (ícono `</>`) si todavía no existe.
2. Copiar la configuración web de Firebase a `firebase-config.js`. No reutilizar el `appId` Android: la aplicación web tiene su propio `appId`.
3. Confirmar que Authentication tenga habilitado el método Email/Password.
4. Servir esta carpeta desde un servidor local o un hosting HTTPS. No abrir `index.html` como archivo local.

## Seguridad de esta fase
- El cliente no llama a `set`, `add`, `update` ni `delete` en Firestore.
- Solo consulta documentos bajo el UID del usuario autenticado.
- No cambiar las reglas de Firestore para esta prueba.
- La vista usa la copia manual como referencia de lectura y muestra el recuento de registros individuales por separado. No se asume que la sincronización automática esté validada.

## Siguiente paso
Comparar los recuentos de esta pantalla con los que muestra Android y confirmar que los datos de `appData/current` estén completos. Solo después se decidirá el esquema compartido y se habilitarán escrituras en una etapa separada.
