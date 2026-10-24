# LeoneraReminders

App de recordatorios para iOS hecha con SwiftUI que usa **AlarmKit** para que cada recordatorio suene como una alarma (aunque el teléfono esté en silencio o en un modo de concentración). No usa dependencias externas: sólo frameworks de Apple (SwiftUI, AlarmKit, AppIntents, Observation) y, para crear recordatorios con la voz o con fotos, la API de [Groq](https://console.groq.com).

## Requisitos

- Xcode 26.1 o posterior (SDK de iOS 26.1).
- iPhone o iPad con iOS 26.0 o posterior.
- Abre `LeoneraReminders.xcodeproj`, elige tu equipo en *Signing & Capabilities* y ejecuta en un dispositivo.
  La primera vez la app pide permiso para programar alarmas (`NSAlarmKitUsageDescription` está en `Config/Info.plist`).

## Qué hace

- **Recordatorio** = título + fecha límite + repetición opcional.
- **Barra flotante abajo**, al estilo de Instagram (una cápsula de vidrio con sólo íconos): **Buscar** (la cambia por el campo de búsqueda) y las
  tres formas de crear: **Foto**, **Voz** y **Manual** (el editor de siempre). Foto y Voz usan Groq y terminan
  en la misma pantalla de revisión:
  - **Voz**: al tocarla empieza a grabar (al principio sólo se habla, no se escribe). Al detener, Whisper la
    convierte en texto; ese texto ya se puede corregir (o *Dictar más*) antes de tocar *Crear recordatorios*.
    En una sola nota caben varios recordatorios («mañana a las 9 llamar al dentista y todos los lunes sacar la basura»).
  - **Foto**: hasta 3 fotos de la cámara o de Fotos (notas, listas, citas, recibos, capturas de pantalla) y, si se
    quiere, indicaciones escritas o dictadas («sólo lo del viernes», «avísame un día antes»).
  - **Revisión**: todos los recordatorios propuestos en una sola lista, cada uno con su título, fecha y hora y
    repetición (frecuencia, cada cuánto, días de la semana o del mes) editables ahí mismo, así que se revisan y
    corrigen sólo desplazándose. Se pueden quitar o agregar más; los que ya pasaron se marcan en rojo. Al guardar
    aparece «N recordatorios agregados» con *Deshacer*.
- **Asistente** (*Configuración → Asistente*): la clave de API de Groq (se guarda en el llavero del iPhone), el
  modelo de **voz a texto** (`whisper-large-v3-turbo` por defecto), el de **texto a recordatorios**
  (`openai/gpt-oss-120b`) y el de **fotos** (`qwen/qwen3.8-27b`, que acepta imágenes), y el idioma del dictado.
  Groq cambia sus modelos seguido, así que *Actualizar lista de modelos* trae los de la cuenta y también se puede
  escribir cualquier id. El modelo responde en JSON (`{"reminders":[{"title","due","repeat"}]}`) con la fecha de hoy
  y los próximos 14 días ya calculados en las instrucciones; la app lo lee de forma tolerante y lo convierte en
  recordatorios con la misma regla de repetición que usa el resto de la app.
- **Repeticiones** (basadas en las del CSV de Due): cada N horas, diario/cada N días, semanal en uno o varios días
  (incluye entre semana y fines de semana), mensual en un día, el último día del mes o un día de la semana del mes (primer, segundo, tercer, cuarto,
  último, penúltimo o antepenúltimo lunes, martes…; cada N meses) y anual (cada N años).
  La regla guarda su propia hora y día, así que mover o posponer una ocurrencia no cambia la regla.
- **Posponer mueve la fecha límite**: «Recordar en 10 min» deja la fecha límite en ahora + 10 min (ya no hay una
  hora de "pospuesto hasta" aparte).
- **Al sonar** la alarma, ningún botón la completa (un toque rápido como «Detener» no debe marcarla por error):
  - **Detener** pospone el tiempo por defecto (10 min).
  - **Abrir app** pospone también y abre la app, donde se completa **deslizando** «Desliza para completar» o se
    elige otro tiempo de "Recordar en…" (1, 5, 10, 20, 40 y 60 min, 2 h y 3 h por defecto; se pueden quitar y agregar).
  - En la lista, deslizar la fila de derecha a izquierda completa directamente (se puede invertir en Configuración → Lista).
  - Desde iOS 26.1 el control Detener lo dibuja el sistema (no se puede cambiar su texto); la app sólo decide qué hace.
- **Si ignoras la alarma, vuelve a sonar**: cada recordatorio deja programadas alarmas extra cada minuto (hasta 10 veces,
  configurable en *Configuración → Si ignoras la alarma*). Como están programadas de antemano, suenan aunque la app
  no esté abierta; al completar o posponer se cancelan todas.
- **Al entrar a la app, ningún vencido se queda callado**: los vencidos (con o sin repetición) que no estén sonando
  vuelven a sonar al empezar el siguiente minuto, y desde ahí siguen las repeticiones. Siguen apareciendo en «Vencidos».
- **Sonido** (*Configuración → Sonido*): Predeterminado del sistema, Campana, Despertador, Ascendente, Marimba, Pulso o
  **Sin sonido**. Los tonos de iOS no están disponibles para otras apps, así que estos van incluidos en la app
  (`LeoneraReminders/Sounds`, sintetizados para el proyecto).
- **«Sonar aunque esté en silencio»**: encendido (por defecto) usa alarmas de AlarmKit, que siempre suenan aunque el
  iPhone esté en silencio o en Concentración. Apagado usa notificaciones locales, que respetan el silencio (sólo
  vibran); tienen los mismos botones, pero iOS sólo guarda 64 pendientes, así que se programan las más próximas.
- **Matriz de ajuste rápido** en el editor: la primera fila fija una hora (10:00, 14:00, 18:00, 21:00), la segunda suma
  (+10 min, +1 h, +1 día, +1 sem.) y la tercera resta. Todas las celdas se cambian en *Configuración*.
  Ahí también se elige desde dónde suman en un recordatorio **vencido** (*Sumar a un vencido*): **desde la fecha
  límite** (por defecto; aunque ya haya pasado) o **desde ahora** (como posponer, ignorando la fecha vencida).
- **Importar CSV** (menú ⋯ → *Importar CSV…*) con las columnas `"Recordatorio","Fecha límite","Repetir"` de Due.
  Muestra una vista previa con avisos, omite duplicados y puede pasar los repetitivos vencidos a su próxima fecha.
  También acepta encabezados en inglés, punto y coma como separador y archivos en UTF-8, UTF-16 o Windows-1252.
- **Exportar CSV** (menú ⋯ → *Exportar CSV…*) guarda todos los recordatorios en un archivo que *Importar CSV…*
  vuelve a leer: las mismas columnas de Due (fecha en ISO 8601, repetición con el mismo resumen que muestra la app)
  más `"Completado"` con la fecha en que se completó, para que los completados no vuelvan como pendientes.
  Va en UTF-8 con BOM para abrirse bien en Excel o Numbers.

## Cómo funciona por dentro

- Cada recordatorio pendiente tiene **alarmas de fecha fija** (la principal y las de repetición) (`Alarm.Schedule.fixed`) en AlarmKit. Las repeticiones
  las calcula la app: al completar, el recordatorio avanza a la siguiente ocurrencia y se programa una alarma nueva.
  (Las repeticiones nativas de AlarmKit sólo cubren "semanal a tal hora".)
- Los botones de la alarma ejecutan `LiveActivityIntent`s (`SnoozeReminderIntent`, `SnoozeOptionsIntent`) dentro del proceso de la app, que actualiza el recordatorio y reprograma.
- `AlarmSyncService` compara los recordatorios con `AlarmManager.alarms` y cancela/programa lo necesario; también
  reprograma si cambian los botones o el tiempo de posponer. Si AlarmKit llega a su límite de alarmas, se programan
  primero las más cercanas.

```
LeoneraReminders/
  App/        Punto de entrada
  Core/       Modelo y lógica sin interfaz (repeticiones, CSV, matriz, configuración, instrucciones y lectura de
              las respuestas de Groq) — probado con `swift test`
  Alarms/     AlarmKit: sincronización, metadatos e intents de los botones
  Assistant/  Groq (peticiones), clave en el llavero, grabación del dictado y fotos
  Stores/     Persistencia (JSON en Application Support y UserDefaults)
  Views/      SwiftUI (Views/Assistant: barra para crear, voz, fotos, revisión y configuración del asistente)
Config/Info.plist
Tests/ReminderCoreTests/
scripts/      Builds firmados: API de App Store Connect (asc.py) y GitHub Pages (publish-pages.sh, pages.py)
```

## Pruebas

La lógica de `LeoneraReminders/Core` también es un paquete de Swift (`Package.swift`) que compila en macOS y Linux:

```sh
swift test
```

## Builds automáticos: instalar desde Safari en el iPhone

`.github/workflows/build.yml` se ejecuta en cada push (a cualquier rama salvo `gh-pages`) y a mano desde
*Actions › Build IPA › Run workflow*. Compila, firma **Ad Hoc** y publica el `.ipa` en un release y en GitHub Pages,
con una página desde la que se instala tocando un botón en Safari.

| Rama | Tag | Release |
|------|-----|---------|
| `main` | `0.x.0` (empieza en `0.1.0`; cada push sube el número del medio) | Estable, marcada como *Latest* |
| cualquier otra | `build-<N>-<commit>` (`N` = número de ejecución del workflow, `commit` = 7 caracteres del hash) | Pre-release, nunca *Latest* |

Ningún build se cancela: los de `main` van en fila (para no repetir versión) y los de otras ramas corren en paralelo.

### Secrets necesarios

En *Settings › Secrets and variables › Actions › Repository secrets* (secrets del repositorio, no de una organización):

| Secret | Qué es |
|--------|--------|
| `ASC_KEY_ID` | Key ID de la clave de API de App Store Connect |
| `ASC_ISSUER_ID` | Issuer ID (aparece arriba de la lista de claves) |
| `ASC_KEY_P8` | Contenido completo del archivo `AuthKey_XXXX.p8` (con las líneas `BEGIN`/`END`) |
| `APPLE_TEAM_ID` | Team ID de la cuenta de Apple Developer (10 caracteres) |

La clave debe ser una **Team Key** (*App Store Connect › Users and Access › Integrations › App Store Connect API*)
con rol **Admin**: Xcode la usa para registrar el App ID, crear los perfiles y firmar con el certificado de
distribución gestionado en la nube.

- **Sin ningún secret** se genera un `.ipa` sin firmar (sólo va al release; hay que firmarlo con Sideloadly, AltStore
  o un certificado propio).
- **Con sólo algunos** el workflow falla indicando cuáles faltan.

### Qué hace cada build firmado

1. `scripts/asc.py check` comprueba con la API de App Store Connect que la clave funciona y que hay al menos un
   dispositivo iOS registrado.
2. `xcodebuild archive` con firma automática (`-allowProvisioningUpdates` y la clave de API). El bundle ID es
   `com.<owner>.<repo>` en minúsculas (aquí `com.leonardoramirezr.leonerareminders`) o el valor de la variable de
   repositorio `APP_BUNDLE_ID` si existe; se pasa a `xcodebuild` como build setting `APP_BUNDLE_ID`, y el proyecto
   usa `$(APP_BUNDLE_ID)` (una extensión usaría `$(APP_BUNDLE_ID).<sufijo>`). La app no usa App Groups ni otras
   capacidades que haya que activar a mano en el portal.
3. `xcodebuild -exportArchive` con `method=release-testing` (Ad Hoc): el perfil incluye **todos los dispositivos
   registrados**. Se verifica que cada bundle lleve un perfil Ad Hoc y se muestra cuántos dispositivos incluye.
4. Se publica en GitHub Pages (`scripts/publish-pages.sh`) y se agrega el enlace de instalación al resumen de la
   ejecución y a las notas del release.
5. Al final se revoca el certificado "Apple Development" temporal que `xcodebuild` crea en cada ejecución.

### Activar GitHub Pages (una sola vez)

Después del **primer build firmado** (que crea la rama `gh-pages`), ve a *Settings › Pages* y en
*Build and deployment* elige *Deploy from a branch*, rama **`gh-pages`** y carpeta **`/ (root)`**.

La página queda en `https://leonardoramirezr.github.io/LeoneraReminders/`: la portada lista todos los builds y tiene
un botón para instalar la última versión estable; cada build tiene su carpeta (`/<tag>/`) con el `.ipa`, el
`manifest.plist` y su propio botón de instalación. La rama `gh-pages` se reescribe en cada publicación como un único
commit (los `.ipa` no se acumulan en el historial) y guarda todas las versiones de `main` y los últimos 50 builds de
otras ramas.

### Añadir un iPhone

Basta con registrar su UDID en [Certificates, Identifiers & Profiles › Devices](https://developer.apple.com/account/resources/devices/list)
y hacer push (o lanzar el workflow a mano): el siguiente build regenera el perfil Ad Hoc con todos los dispositivos
registrados. Los builds anteriores sólo se instalan en los dispositivos que ya estaban registrados cuando se hicieron.
