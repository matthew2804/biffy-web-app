# Biffy · App móvil (Flutter)

Aplicación de domicilios de comida para estudiantes universitarios en Colombia, con tres roles conectados: **comprador**, **restaurante** y **repartidor**. Sprint 1: frontend funcional en Flutter con datos simulados (sin backend, sin pagos reales, sin GPS).

> La app web anterior (React/Lovable) se conserva solo como referencia en [`legacy_web/`](legacy_web/).

## Requisitos

- Flutter 3.44 o superior (probado con Flutter 3.44.8 / Dart 3.12.2).
- Para Android: Android SDK / Android Studio y un emulador o teléfono con depuración USB.

## Comandos (desde la raíz del repositorio)

```bash
flutter pub get                 # dependencias
flutter run                     # ejecutar en el dispositivo conectado
flutter run -d chrome           # ejecutar en el navegador (vista previa)
dart format .                   # formato
flutter analyze                 # análisis estático
flutter test                    # pruebas unitarias, de widgets e integración (sin dispositivo)
flutter test integration_test/app_test.dart -d <dispositivo>   # integración en Android/iOS
flutter build apk --debug       # APK de depuración (requiere Android SDK)
```

## Cuentas de demostración

Contraseña de todas: `biffy123` (también hay botones de acceso rápido en la pantalla de login).

| Rol | Correo |
|---|---|
| Comprador con historial (Icesi verificado, simulado) | `diego.demo@icesi.edu.co` |
| Comprador nuevo | `camila.demo@biffy.co` |
| Repartidor (moto) | `andres.repartidor@demo.biffy.co` |
| Repartidora (bicicleta) | `valentina.repartidora@demo.biffy.co` |
| Restaurante Qbano Icesi (demo) | `qbano@demo.biffy.co` |

Si pruebas de noche y todo aparece cerrado, activa **Configuración › Horario de demostración (12:00)**.

Consulta el informe completo en [`INFORME_SPRINT_1.md`](INFORME_SPRINT_1.md).
