# Mis gastos — MVP Flutter

Aplicación móvil en español para registrar gastos, organizar categorías, consultar un gráfico y controlar un presupuesto semanal. Funciona sin cuenta en el dispositivo; Firebase Auth y Firestore añaden inicio de sesión y sincronización cuando se proporcionan credenciales.

## Requisitos

- Flutter 3.24 o superior y Dart 3.3 o superior.
- Xcode para iOS y Android Studio/SDK para Android.
- Un proyecto Firebase con Email/Password habilitado y Cloud Firestore creado para habilitar la nube.

## Instalación

Las carpetas de plataforma Android e iOS ya están generadas. Desde esta carpeta:

```sh
flutter pub get
flutter analyze
flutter test
```

Para ejecutar exclusivamente en modo local:

```sh
flutter run
```

La app no necesita cuenta para el CRUD local. El primer inicio crea las categorías de ejemplo y una llave AES-256 en el almacenamiento seguro del sistema.

## Firebase (opcional)

Obtén los valores de la configuración de la app en Firebase Console. No guardes credenciales en el repositorio. Pásalos durante la ejecución:

```sh
flutter run \
  --dart-define=FB_API_KEY=tu_api_key \
  --dart-define=FB_APP_ID=tu_app_id \
  --dart-define=FB_MESSAGING_SENDER_ID=tu_sender_id \
  --dart-define=FB_PROJECT_ID=tu_project_id
```

Activa Email/Password en **Authentication → Sign-in method**, crea la base de **Cloud Firestore** y publica las reglas de [`firestore.rules`](./firestore.rules). Cada usuario solo puede leer y escribir sus propios documentos. El SDK de Firebase administra los tokens; la app no los registra ni persiste manualmente.

Al iniciar sesión por primera vez, la app vincula la copia local a ese UID. Después combina registros locales y remotos por ID (los locales prevalecen en conflictos) y sube el resultado; así, una cuenta nueva no borra los datos del dispositivo. Para evitar filtrar datos entre cuentas, la copia local no se sincroniza con un UID distinto. Cada sincronización elimina de la nube los documentos que ya no están en la copia local; las eliminaciones pendientes quedan registradas localmente hasta confirmarse. Las modificaciones se guardan primero en el dispositivo. Si no hay red, el error de sincronización queda visible y los datos locales permanecen.

## Permisos de plataforma

Las carpetas nativas ya incluyen `android.permission.CAMERA`, `android.permission.POST_NOTIFICATIONS` y `NSCameraUsageDescription`. En iOS, confirma el permiso de notificaciones al primer uso; en Android 13 o posterior el plugin solicita permiso en tiempo de ejecución.
- Ejecuta en un dispositivo real para probar la cámara y las notificaciones.

La imagen del ticket se cifra con AES-GCM antes de guardarse en el directorio privado de la app. Las notificaciones se programan al detectar el cruce del umbral semanal del 80%; el sistema operativo puede retrasar notificaciones no exactas.

## Funcionalidad

- CRUD de gastos, seis categorías iniciales y presupuesto semanal.
- Límites semanales globales o por categoría, alertas al 80%, búsqueda y filtro mensual.
- Base SQLite local con relaciones gasto→categoría y presupuesto→categoría opcional.
- Cifrado AES-256-GCM de importes, descripciones, notas, presupuestos y archivos de tickets. La llave se guarda con `flutter_secure_storage` en Keychain/Keystore.
- Captura con cámara (`image_picker`), gráfico (`fl_chart`) y formato de moneda/fecha (`intl`).
- Firebase Auth por correo y contraseña; sincronización autenticada con Firestore.
- Validación de importes, correo, contraseña y longitudes; estados de carga y errores de persistencia/sincronización.

## Pruebas

`test/models_test.dart` cubre validaciones de importes, descripción, correo, contraseña y filtros de historial. Verificado con Flutter 3.50.1: `flutter analyze` sin problemas y `flutter test` aprobado.

## Repositorio y ramas

Repositorio público: <https://github.com/xGodlight/gastos_flutter>.

- `main`: rama estable.
- `develop`: rama de integración.
- `feature/login`: recuperación segura de contraseña y manejo de sesión.
- `feature/receipt-preview`: vista descifrada de tickets.
- `feature/expense-management`: gestión de límites, alertas y búsqueda.
- `hotfix/sqlite-sync-migration`: migración segura de SQLite.

Pull requests:

- [`feature/login` → `develop` (#1)](https://github.com/xGodlight/gastos_flutter/pull/1), con autorevisión documentada en [`docs/revision-feature-login.md`](./docs/revision-feature-login.md).
- [`feature/receipt-preview` → `develop` (#2)](https://github.com/xGodlight/gastos_flutter/pull/2).
- [`hotfix/sqlite-sync-migration` → `main` (#3)](https://github.com/xGodlight/gastos_flutter/pull/3).
- [`feature/expense-management` → `develop` (#4)](https://github.com/xGodlight/gastos_flutter/pull/4).

Los cambios están publicados en sus ramas y los PR permanecen abiertos; no se han mezclado automáticamente.

El reporte técnico en Markdown —con diagrama de clases, modelo de datos y mecanismos de seguridad— está en [`docs/reporte-tecnico.md`](./docs/reporte-tecnico.md).

Para empaquetar iOS, preparar la ficha de tienda y revisar clasificación de edad, consulta la [guía de publicación en App Store](./docs/guia-publicacion-appstore.md).
