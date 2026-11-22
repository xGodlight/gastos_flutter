# Autorevisión — `feature/login`

**Destino:** `develop`  
**Revisión:** autorevisión documentada  
**Alcance:** autenticación Firebase, recuperación de contraseña y manejo de sesión.

## Cambios revisados

- La recuperación solicita un correo con formato válido y utiliza una respuesta genérica para no revelar si la dirección está registrada.
- Los errores de Firebase se convierten en mensajes en español; no se muestran mensajes internos arbitrarios del proveedor.
- El formulario evita envíos duplicados, permite mostrar/ocultar la contraseña y libera los controladores tras cerrar el diálogo.
- La suscripción a cambios de autenticación se cancela al destruir la pantalla.
- Firebase Auth conserva la gestión de las credenciales; no se persiste ni registra la contraseña.

## Validación

- `dart format lib/app.dart lib/cloud_service.dart lib/auth_error_message.dart test/models_test.dart`
- `flutter analyze` — sin problemas.
- `flutter test` — 5 pruebas aprobadas, incluidas las pruebas de mensajes de error.

## Decisión

Sin defectos adicionales conocidos en el alcance revisado. La prueba de extremo a extremo de Firebase requiere configurar un proyecto y habilitar Email/Password; no se afirma que se haya ejecutado con credenciales reales.
