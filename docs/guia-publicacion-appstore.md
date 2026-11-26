# Guía de publicación en App Store — Mis gastos

Guía de preparación para distribuir la versión iOS del MVP. Incluye el firmado y empaquetado con Xcode, una ficha de tienda simulada y una propuesta de respuestas para las clasificaciones de edad. La clasificación final la asignan Apple y las autoridades IARC según las respuestas definitivas y la versión enviada.

> **Estado:** guía de publicación; todavía no significa que la app esté lista o aprobada para la tienda. Antes de enviar hay que resolver los bloqueadores indicados en [Preparación pendiente del MVP](#8-preparación-pendiente-del-mvp).

## 1. Requisitos previos

- Mac con una versión de Xcode aceptada actualmente por App Store Connect y los componentes de iOS instalados.
- Flutter y CocoaPods instalados. En este proyecto, verificar `flutter doctor -v`, ejecutar `flutter pub get` y `cd ios && pod install`.
- Inscripción activa en el [Apple Developer Program](https://developer.apple.com/programs/), acceso a App Store Connect y acuerdos vigentes aceptados.
- Un App ID explícito y un identificador de paquete propio y definitivo. El proyecto generado todavía usa `com.example.gestionGastosPersonales`: **reemplazarlo antes de registrar la app**, por ejemplo por un identificador reverse-DNS que controles, como `com.tudominio.misgastos`. Debe coincidir en Xcode, App Store Connect y el perfil de aprovisionamiento.
- Proyecto Firebase de producción configurado si se ofrecerán registro e inicio de sesión. Firestore debe tener las reglas de [`../firestore.rules`](../firestore.rules).
- Política de privacidad pública, URL de soporte, icono final, capturas de pantalla y cuenta de demostración si el revisor necesita entrar a funciones protegidas.

## 2. Certificados, App ID y provisioning profile

### Firmado automático (recomendado)

En Xcode, abre `ios/Runner.xcworkspace`, selecciona el target **Runner** y ve a **Signing & Capabilities**:

1. Selecciona tu **Team** de Apple Developer.
2. Activa **Automatically manage signing**.
3. Establece el **Bundle Identifier** único y definitivo.
4. Comprueba que las capacidades declaradas sean solo las que la app necesita.
5. Repite la comprobación en los targets de configuración relevantes (Debug/Release).

Xcode puede crear y mantener los activos de firma de distribución. Conserva el certificado y su llave privada en el llavero del equipo autorizado; no los incluyas en Git ni los compartas.

### Qué activos intervienen

| Activo | Propósito en esta publicación |
|---|---|
| **App ID explícito** | Identifica esta app individual. Su Bundle ID debe coincidir exactamente con `PRODUCT_BUNDLE_IDENTIFIER` y con el registro de App Store Connect. |
| **Apple Distribution certificate** | Firma la app para distribuirla mediante App Store Connect. Pertenece al equipo de desarrollo. |
| **App Store Connect provisioning profile** | Asocia el App ID explícito y un certificado de distribución autorizado para subir la app. Xcode puede administrarlo automáticamente. |
| **Apple Development certificate / perfil de desarrollo** | Sirve para ejecutar y depurar en dispositivos registrados; no es el perfil de publicación. |

Si se opta por firma manual: en **Certificates, Identifiers & Profiles**, registrar el App ID explícito; crear un certificado **Apple Distribution**; crear un perfil **App Store Connect** para ese App ID y certificado; descargarlo e instalarlo. El perfil de distribución de App Store Connect no se configura con la lista de UDID de dispositivos de pruebas. Apple detalla el proceso de [App IDs](https://developer.apple.com/help/account/identifiers/register-an-app-id/), [certificados](https://developer.apple.com/help/account/certificates/certificates-overview/) y [perfiles de App Store Connect](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/).

La app usa notificaciones **locales**; no requiere certificado APNs para esa función. Si se añade notificación push en el futuro, se debe configurar la capacidad y las credenciales de APNs por separado.

## 3. Generar el archive y el IPA

### Opción A: Flutter desde Terminal

Desde la raíz del proyecto, luego de fijar el Bundle ID y configurar la firma iOS en Xcode:

```bash
flutter doctor -v
flutter pub get
cd ios
pod install
cd ..
flutter analyze
flutter test
flutter build ipa --release --build-name=1.0.0 --build-number=1
```

La compilación produce el archivo `.xcarchive` y el IPA de distribución en `build/ios/`. Conserva también el `.xcarchive`, porque sirve para volver a subir builds con símbolos de depuración. Cada envío necesita un número de build nuevo. `--build-name` corresponde a la versión visible y `--build-number` al número interno.

### Opción B: Xcode Organizer

1. Ejecuta `flutter pub get` y `cd ios && pod install`.
2. Abre `ios/Runner.xcworkspace` en Xcode (no el `.xcodeproj`).
3. Selecciona el esquema **Runner** y un destino de archivo, como **Any iOS Device (arm64)**; no selecciones un simulador.
4. En **Runner → General**, confirma el Bundle ID, la versión y el número de build.
5. En **Signing & Capabilities**, confirma el Team y la firma automática o manual.
6. Selecciona **Product → Archive**. Al terminar, Organizer abrirá el archive.
7. Usa **Validate App** para la validación previa.
8. En **Distribute App**, selecciona **App Store Connect**:
   - Elige **Upload** para enviar el build directamente; es la ruta recomendada para TestFlight y App Store.
   - Elige **Export** si necesitas guardar localmente el paquete firmado y cargarlo más tarde con Transporter. Xcode ofrece un IPA cuando la opción de exportación lo permite.
9. Espera el procesamiento de Apple en App Store Connect y revisa sus mensajes y correo de entrega.

En el flujo de publicación habitual no hace falta adjuntar manualmente un IPA en la ficha: se sube el archive mediante Xcode. Si se exportó un IPA, [Transporter](https://apps.apple.com/app/transporter/id1450874784) puede entregarlo a App Store Connect. Sigue las instrucciones actuales de Apple para [distribuir con Xcode](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases) y [subir builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

## 4. Ficha de App Store simulada

Propuesta en español de México. El nombre puede no estar disponible; comprobarlo al crear el registro. Los textos describen únicamente funciones incluidas en el MVP.

| Campo | Propuesta |
|---|---|
| **Nombre** | **Mis gastos: presupuesto** |
| **Subtítulo** | **Control de gastos y tickets** |
| **Categoría principal** | Finanzas |
| **Categoría secundaria** | Productividad |
| **Idioma principal** | Español (México) |
| **Precio** | Gratis (MXN $0). Sin compras dentro de la app ni suscripción en este MVP. |
| **Distribución inicial** | México únicamente. Considerar Chile, Colombia, España y Estados Unidos después de revisar localización, soporte y requisitos legales de cada territorio. |
| **URL de soporte** | `https://TU-DOMINIO/soporte` — reemplazar por una página pública real antes del envío. |
| **Política de privacidad** | `https://TU-DOMINIO/privacidad/mis-gastos` — reemplazar por la política definitiva, pública y específica para la app. |
| **URL de marketing** | Opcional: `https://TU-DOMINIO/mis-gastos` |

### Descripción corta / subtítulo

> Controla gastos y presupuestos semanales, organiza compras y guarda fotos de tus tickets.

Usar como propuesta del subtítulo si cumple el límite vigente que muestre App Store Connect. Apple ya dispone de un campo de subtítulo; no confundirlo con la descripción extensa.

### Descripción larga

> **Organiza tus gastos personales y consulta cómo va tu presupuesto semanal.**
>
> Mis gastos te ayuda a llevar un registro sencillo de tus compras desde el móvil. Añade cada gasto, asígnalo a una categoría y consulta el total junto con un gráfico para entender mejor en qué se va tu dinero.
>
> **Lleva el control**
> - Registra, consulta, edita y elimina gastos.
> - Organiza movimientos por categorías como comida, transporte, hogar, salud y ocio.
> - Busca por descripción o filtra el historial del mes.
> - Define presupuestos semanales generales o por categoría.
> - Recibe una notificación local cuando tus gastos llegan al 80% de un presupuesto.
>
> **Conserva tus tickets**
> - Captura el ticket con la cámara y asócialo a un gasto.
> - Las fotos de tickets se guardan cifradas en el dispositivo y se pueden volver a consultar desde la app.
>
> **Empieza sin cuenta**
> El registro y la consulta local funcionan sin iniciar sesión. Si se configura Firebase, puedes crear una cuenta e iniciar sesión para sincronizar descripciones, importes, categorías y fechas de gastos, además de presupuestos, con tu cuenta. La sincronización requiere conexión a internet.
>
> Los importes, descripciones, notas, presupuestos y fotos se cifran en el almacenamiento local de la app. Los datos sincronizados con Firebase se transmiten mediante el SDK de Firebase, pero no tienen cifrado de extremo a extremo implementado por esta app. Las fotos de tickets no se sincronizan con Firebase.
>
> Mis gastos es una herramienta de organización personal. No es un banco, no conecta cuentas bancarias y no proporciona asesoramiento financiero.

**Palabras clave sugeridas** (campo de palabras clave de App Store Connect; validar el límite actual y evitar repetir términos ya incluidos en el nombre/subtítulo):

```text
finanzas,ahorro,control,compras,registro,mensual,categorías,recibos
```

**Texto promocional opcional:**

> Registra tus compras, organiza tus tickets y descubre qué categorías consumen tu presupuesto semanal.

### Capturas y material gráfico

Preparar capturas reales de la versión iOS para los tamaños de pantalla que App Store Connect solicite al crear la ficha. Recomendación: inicio/resumen, distribución por categoría, creación de gasto, captura/consulta de ticket, presupuesto general y límite por categoría. No añadir pantallas o funciones que no aparezcan en la app. Preparar icono final, no usar assets de placeholder.

## 5. Clasificación de edad: cuestionarios simulados

Las respuestas siguientes son una **previsión para el MVP actual**. Responder el formulario real según el binario, el contenido descargable, el comportamiento de los SDK y las políticas vigentes. No elegir una clasificación manualmente ni responder en función solo de la audiencia deseada.

### Apple — App Store Connect

En **App Information → Age Rating**, Apple solicita información sobre contenido, capacidades e interacciones; calcula la clasificación por región y puede mostrar diferentes bandas dependiendo de la versión del sistema operativo. La guía actual enumera las bandas nuevas para iOS 26 o posterior y conserva las correspondientes a sistemas anteriores.

| Sección/tema | Respuesta propuesta para esta versión |
|---|---|
| Violencia, armas, horror/miedo | Ninguno |
| Lenguaje, humor vulgar, alcohol/tabaco/drogas | Ninguno |
| Contenido sexual, desnudez, temas románticos/maduros | Ninguno |
| Temas médicos o de tratamiento | Ninguno |
| Apuestas o simulación de apuestas | No |
| Acceso web sin restricciones | No |
| Chat, mensajería o red social | No |
| Contenido creado por usuarios de amplia distribución | No. Las descripciones y fotos son registros privados del propietario, no se publican ni distribuyen a otros usuarios. |
| Publicidad | No |
| Controles parentales / verificación de edad | No |
| Compras dentro de la app | No |

Resultado esperado: clasificación de la banda más baja disponible (previsiblemente **4+** para dispositivos con categorías nuevas), pendiente del resultado oficial. La función de cuentas de Firebase no convierte por sí sola el contenido financiero privado en una red social o contenido público.

### Google Play — IARC (referencia para una futura publicación Android)

Este cuestionario es para Google Play Console; no sustituye el de Apple. Google asigna clasificaciones por región a partir de las respuestas.

| Pregunta o tema del cuestionario | Respuesta simulada |
|---|---|
| Violencia, sexualidad, lenguaje ofensivo, drogas o apuestas | No |
| Interacción/funciones sociales entre usuarios | No |
| Contenido creado por usuarios que se comparte con otros | No |
| Ubicación precisa compartida públicamente | No |
| Compras o transacciones digitales dentro de la app | No para este MVP |
| Anuncios | No |
| Público objetivo | No dirigida a menores; público adulto/general que administra gastos personales |

Resultado orientativo: clasificación general de baja edad (por ejemplo, **Everyone / PEGI 3**, según territorio), únicamente si las respuestas y la revisión IARC lo confirman. En Play Console también se debe completar la declaración de anuncios, audiencia, acceso a la app, seguridad de datos y política de privacidad; estas preguntas no son todas parte del rating IARC.

Referencias: [clasificación por contenido en Google Play](https://support.google.com/googleplay/android-developer/answer/9859655) y [preparar una app para revisión en Play Console](https://support.google.com/googleplay/android-developer/answer/9859455).

## 6. Precio y territorios

Propuesta de lanzamiento:

- **Precio base:** gratis; no se habilitan compras integradas ni suscripción.
- **País inicial:** México.
- **Ampliación posterior:** habilitar territorios adicionales desde App Store Connect, después de revisar traducciones, soporte, obligaciones de privacidad y requisitos locales.

En App Store Connect, configura **Pricing and Availability** según las opciones actuales de la cuenta y comprueba la tienda/moneda del territorio antes de publicar. Precio y disponibilidad pueden cambiar; confirma impuestos, acuerdos y condiciones vigentes del programa en la consola.

## 7. Completar la ficha y enviar a revisión

1. En App Store Connect, confirma los acuerdos del equipo y crea un registro nuevo para iOS con nombre disponible, idioma principal, Bundle ID explícito y SKU único. Apple exige que exista el registro antes de la carga del build. Consulta [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).
2. En **App Information**, completa nombre, subtítulo, categorías, clasificación de edad y derechos de contenido.
3. En **App Privacy**, publica una URL de privacidad real y responde por los datos que la app y sus SDK recopilan. Como mínimo, audita la cuenta de correo/ID de usuario de Firebase y los registros de gastos sincronizados; confirma con la pantalla vigente cómo clasifica Apple los datos financieros y las finalidades. No declares “no recopila datos” si Firebase está habilitado y sincroniza datos personales. Revisa también recopilación de diagnósticos/identificadores por SDK y configuración.
4. En **Pricing and Availability**, fija gratis y México como territorio inicial.
5. Completa descripción, palabras clave, URL de soporte y capturas para todos los tamaños requeridos.
6. Configura la versión de iOS, incrementa el build number y genera el archive/IPA con uno de los procesos de la sección 3.
7. Sube el archive a App Store Connect y espera a que el build termine de procesarse.
8. Para una prueba previa, habilita TestFlight, añade testers y valida registro, alta/baja de cuenta, CRUD local, captura y reapertura de tickets, notificaciones y sincronización.
9. Selecciona el build procesado en la versión de la app. Completa el cuestionario de exportación/cifrado con información exacta: el MVP utiliza AES-GCM para datos en reposo y TLS del SDK para nube; no marques una exención sin confirmar que corresponde a la implementación y normativa.
10. En **App Review Information**, proporciona instrucciones y una cuenta de prueba activa si el revisor debe acceder a Firebase, junto con cualquier requisito para reproducir cámara/notificaciones. No pegues credenciales en el repositorio ni en esta guía.
11. Pulsa **Add for Review / Submit for Review** y responde a cualquier pregunta o rechazo desde App Store Connect.
12. Tras la aprobación, publica manualmente o deja el lanzamiento automático según la opción seleccionada. Verifica la ficha y la descarga en la tienda de México.

## 8. Preparación pendiente del MVP

Resolver estos puntos antes de solicitar revisión de producción:

1. **Cambiar Bundle ID de ejemplo:** Xcode actualmente usa `com.example.gestionGastosPersonales`. Elegir un identificador permanente bajo un dominio/control propio y aplicarlo a Runner y App Store Connect antes del primer registro.
2. **Eliminar cuenta dentro de la app:** el MVP ofrece crear una cuenta Firebase, pero todavía no implementa eliminación de cuenta desde la interfaz ni borrado asociado de Firestore. Como la app permite crear cuentas, Apple requiere que el usuario pueda iniciar su eliminación desde la app. Implementar el flujo y comprobar qué datos se borran antes de enviar.
3. **Publicar y enlazar documentos reales:** política de privacidad y soporte actualmente son valores de ejemplo; necesitan páginas públicas funcionales que describan Firebase, gastos, almacenamiento local, retención y eliminación.
4. **Configurar Firebase de producción:** configurar Auth, Firestore, reglas y acceso para revisión; probar en iOS real con una cuenta de prueba.
5. **Permisos y experiencia final:** confirmar en dispositivo iOS permisos de cámara/notificaciones, comportamiento cuando el usuario los rechaza, accesibilidad y ausencia de errores.
6. **Datos de tienda:** validar nombre disponible, copy, capturas, icono, clasificación, territorios, export compliance y etiquetas de privacidad. Las respuestas propuestas aquí no son una determinación legal ni garantía de aprobación.
7. **Distribución técnica:** verificar en Xcode el destino iOS vigente, Pods, firmado, archive, validación de Apple y build procesado.

La eliminación de cuenta es especialmente importante: no enviar una versión que permita registrarse pero no iniciar la eliminación de la cuenta desde la propia app. Revisar la sección 5.1.1 de las [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## 9. Fuentes oficiales

- [Distribuir una app con Xcode](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Subir builds a App Store Connect](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Registrar un App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/)
- [Certificados de Apple](https://developer.apple.com/help/account/certificates/certificates-overview/)
- [Crear un provisioning profile de App Store Connect](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/)
- [Añadir una app a App Store Connect](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Clasificaciones de edad Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- [Privacidad de la app en App Store Connect](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Clasificaciones IARC de Google Play](https://support.google.com/googleplay/android-developer/answer/9859655)
- [Preparar una app para revisión en Google Play](https://support.google.com/googleplay/android-developer/answer/9859455)
