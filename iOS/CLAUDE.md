# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Este es el wrapper iOS de Vetify. El wrapper Android equivalente vive en `../Android` (ver su propio `CLAUDE.md`).

## Build y ejecución

El proyecto activo es **`vetify.xcodeproj`** (no usa CocoaPods ni SPM). `Vetify-app.xcodeproj` es un proyecto legacy sin `project.pbxproj` — ignorarlo.

Hay dos schemes, uno por entorno:

```bash
# Build de QA
xcodebuild -project vetify.xcodeproj -scheme vetify-qa -configuration Debug build

# Build de Prod
xcodebuild -project vetify.xcodeproj -scheme vetify -configuration Debug build

# Correr en simulador
xcodebuild -project vetify.xcodeproj -scheme vetify-qa \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Para el día a día normalmente se abre `vetify.xcodeproj` en Xcode y se elige el scheme `vetify` o `vetify-qa`. No hay tests en el proyecto.

- **Deployment target:** iOS 18.0
- **Versión:** `MARKETING_VERSION` 3.3, `CURRENT_PROJECT_VERSION` (build) 9

## Arquitectura

App **wrapper de WKWebView de un solo `ViewController`** que carga la web app Vetify. Toda la lógica vive en `Vetify-app/ViewController.swift`; `AppDelegate`/`SceneDelegate` son el boilerplate por defecto de Xcode. La UI raíz se arma vía storyboard `Main` (ver `Info.plist` / `Base.lproj`).

`ViewController` (implementa `WKNavigationDelegate`, `WKUIDelegate`, `UIImagePickerControllerDelegate`) maneja:
- Carga de `AppConfiguration.baseURL`, con `UIProgressView`, pull-to-refresh y botón de compartir.
- **Monitoreo de red** con `NWPathMonitor`: alerta "Sin conexión" cuando se pierde internet.
- **Ruteo de URLs** en `decidePolicyFor navigationAction`: `mailto:`/`tel:` y hosts fuera de `AppConfiguration.allowedHost` se abren en apps del sistema (`UIApplication.open`); `window.open()` se intercepta en `createWebViewWith`.
- **PDFs**: se interceptan tanto por extensión `.pdf` como por `mimeType application/pdf` en `decidePolicyFor navigationResponse`, se descargan con `URLSession` y se presentan vía `UIActivityViewController`.
- **`input type="file"`**: `runOpenPanelWith` abre `UIImagePickerController` (cámara si está disponible, si no galería) y devuelve la URL al WebView por el `imagePickerCompletion`.

### Inyección de CSS/JS

`makeWebViewWithCustomScripts()` inyecta `Vetify-app/style.css` (en `.atDocumentEnd`) y `Vetify-app/script.js` (envuelto en `DOMContentLoaded`, `.atDocumentStart`) en cada carga. **Hoy ambos archivos están vacíos** (placeholders de 1 byte) — son el punto de enganche para adaptar la web al móvil, igual que `assets/script.js` / `assets/styles.css` en Android.

## Configuración por entorno

La selección de entorno se hace con **xcconfig por scheme**, no hardcodeada:

- `Vetify-app/Configurations/Prod.xcconfig` → bundle `com.vetify.webapp`, `https://vetify.ikeapp.com/`, flag `VETIFY_PROD`.
- `Vetify-app/Configurations/QA.xcconfig` → bundle `com.vetify-qa.webapp`, `https://vetify-qa.ikeapp.com/`, flag `VETIFY_QA`, app icon `AppIcon-QA`.

`AppConfiguration` (`Vetify-app/AppConfiguration.swift`) resuelve `baseURL` y `allowedHost` con esta precedencia: **claves `BASE_URL`/`HOST` del Info.plist primero** (inyectadas vía `INFOPLIST_KEY_*` desde el xcconfig), y como fallback los flags de compilación `VETIFY_QA`/`VETIFY_PROD`. Los valores del plist que quedan sin sustituir (contienen `$(`) se ignoran. **Para agregar/cambiar un entorno se edita el xcconfig correspondiente**, no el código.

Las descripciones de permisos (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`) y `NSAppTransportSecurity` (`NSAllowsArbitraryLoads = true`) se definen vía `INFOPLIST_KEY_*` en build settings / `Info.plist`.
