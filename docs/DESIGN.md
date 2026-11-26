# Diseño técnico — Mac Resource Monitor

Estado: **borrador v0.1** (2026-11-26). Acompaña a [REQUIREMENTS.md](REQUIREMENTS.md).

> **Decisión confirmada (2026-11-26, Cabezon):** Swift nativo, solo macOS. Los detalles finos de abajo (AppKit + SwiftUI, gráficos propios, Swift Package, macOS 13+) siguen siendo propuesta y se pueden revisar.

## 1. Stack recomendado

**Swift 5.10+ nativo, AppKit para la barra de menú + SwiftUI para el contenido del popover.** Sin Electron, sin Python, sin dependencias externas.

| Opción | RAM típica | Por qué sí / no |
|---|---|---|
| **Swift + AppKit/SwiftUI** ✅ | 15–25 MB | Llamadas directas al kernel (Mach, IOKit, sysctl), sin runtime extra, look nativo gratis. |
| SwiftUI `MenuBarExtra` puro | 20–30 MB | Más simple pero menos control sobre el ícono dinámico y el ciclo de vida del popover. |
| Tauri / Rust | 40–80 MB | WebView = más memoria y look no nativo. |
| Electron | 150+ MB | Descartado. |

Detalles:
- `NSStatusItem` con un ícono dibujado a mano (template image + puntito de color). Se redibuja **solo cuando cambia el estado**, no en cada muestra.
- `NSPopover` con un `NSHostingView` de SwiftUI. La vista **se crea al abrir y se destruye al cerrar**, así con el popover cerrado no hay árbol de vistas en memoria.
- Gráficos: `Canvas`/`Path` de SwiftUI propios (sparklines). Swift Charts es más pesado y no hace falta para líneas simples.
- Login item: `SMAppService.mainApp.register()` (macOS 13+).
- Target mínimo: **macOS 13 Ventura** **[SUPUESTO]**. Universal (Apple Silicon + Intel).
- `LSUIElement = YES` (sin ícono en el Dock).

## 2. Arquitectura

```
┌────────────── App (proceso único) ──────────────┐
│ Sampler (1 DispatchSourceTimer, con leeway)     │
│   ├─ CPUProbe      host_processor_info          │
│   ├─ MemoryProbe   host_statistics64 + pressure │
│   ├─ DiskProbe     statfs + IOKit block stats   │
│   ├─ PowerProbe    IOKit AppleSmartBattery      │
│   ├─ NetProbe      sysctl NET_RT_IFLIST2        │
│   └─ PingProbe     socket ICMP no privilegiado  │
│          │                                      │
│          ▼                                      │
│ MetricStore (ring buffers de Float32)           │
│          │                                      │
│   ┌──────┴────────┐                             │
│   ▼               ▼                             │
│ HealthEvaluator  PopoverView (solo si abierto)  │
│   │ (umbrales + histéresis)                     │
│   ▼                                             │
│ StatusItemController (redibuja si cambia)       │
└─────────────────────────────────────────────────┘
```

Módulos (Swift Package):
- `MonitorCore` — probes, store, evaluador de salud. Sin UI, testeable.
- `MonitorApp` — status item, popover, ajustes.

## 3. Cómo se mide cada cosa (sin privilegios de root)

| Métrica | API | Costo |
|---|---|---|
| CPU % | `host_processor_info` → delta de ticks user+system+nice / total | 1 syscall |
| Memoria | `host_statistics64(HOST_VM_INFO64)`: app + wired + compressed. Presión: `sysctl kern.memorystatus_vm_pressure_level` | 2 syscalls |
| Disco espacio | `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` del volumen raíz, cada 30 s (cambia lento) | despreciable |
| Disco I/O | IOKit `IOBlockStorageDriver` → `Statistics` bytes leídos/escritos, delta | 1 consulta IOKit |
| Batería W | IOKit `AppleSmartBattery`: `Voltage × InstantAmperage`. Enchufada: `PowerTelemetryData.SystemPowerIn` | 1 consulta IOKit |
| Red | `sysctl(NET_RT_IFLIST2)` con contadores de 64 bits (`getifaddrs` usa 32 bits y desborda a ~4 GB) | 1 syscall |
| Ping | `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` — macOS lo permite sin root. Para destinos que bloquean ICMP (ej. endpoints AWS) se usa **latencia de conexión TCP :443** | 1 paquete/destino |
| Gateway | tabla de rutas vía `sysctl(NET_RT_FLAGS)` → ruta default | al cambiar de red |

Nunca se lanzan procesos (`ping`, `top`, `ioreg`): crear procesos es lo más caro.

## 4. Cadencia de muestreo y ahorro

| Estado | CPU/Mem/Red/Disco I/O | Ping ICMP | Ping TCP | Batería | Disco espacio |
|---|---|---|---|---|---|
| Siempre (popover abierto o cerrado) | cada 1 s | cada 1 s, todos los destinos | cada 5 s | cada 2 s | cada 30 s |
| Mac dormida / pantalla apagada | pausado | pausado | pausado | pausado | pausado |

Se muestrea a 1 s siempre para que el historial sea continuo: cada tick son ~6 syscalls (microsegundos). Con el popover cerrado no se arma historial para la UI ni se dibuja nada. Si las mediciones reales superan el presupuesto, se pasa a 2 s con el popover cerrado.

- **Un solo timer** con `leeway` para que el sistema agrupe wakeups.
- Todas las probes corren en una cola serial de baja prioridad (`.utility`).
- Sin `Timer` de SwiftUI ni animaciones continuas.
- Con el popover cerrado no se dibuja nada salvo un cambio de color del ícono.

## 5. Historial

Ring buffers de `Float32` por métrica:
- 30 s a 1 s/muestra (o 2 s con popover cerrado)
- 5 min a 5 s/muestra (promedio)
- 1 h a 30 s/muestra (promedio; para ping se guarda también el máximo)

Total ≈ 10 series × ~250 puntos × 4 bytes ≈ **10 KB**. En memoria, no se persiste en v1.

## 6. Salud y semáforo

`HealthEvaluator` aplica los umbrales de REQUIREMENTS §4 con histéresis (subir de nivel requiere N muestras seguidas, bajar requiere M). El estado global es el peor de todos. El popover ordena: primero las métricas no‑verdes, luego el resto.

## 7. Ícono

Template image monocromo (se adapta a claro/oscuro y al resaltado de la barra) de ~16 pt, más un puntito de 5 pt abajo a la derecha:
- Verde: punto verde sistema (`systemGreen`), discreto.
- Amarillo: `systemYellow`.
- Rojo: `systemRed`.
Alternativa a confirmar: en verde no mostrar punto (estilo Apple puro: solo aparece color cuando hay algo para mirar), y opcionalmente mostrar el ping en ms al lado del ícono.

## 8. Build, CI y distribución

- Proyecto como **Swift Package** + script `scripts/bundle.sh` que arma el `.app` (Info.plist, firma ad‑hoc). No depende de un `.xcodeproj` y se puede compilar con `swift build`.
- CI en GitHub Actions con runner `macos-15`: compila, corre tests de `MonitorCore` y publica el `.app` zipeado como artefacto de cada PR.
  - Nota: el repo es privado, y los minutos de macOS en GitHub cuentan x10 sobre la cuota gratis (2.000 min/mes → ~200 min macOS). Cada build debería tardar 2–4 min.
- Distribución: sin cuenta Apple Developer, la app va firmada ad‑hoc; la primera vez hay que abrirla con clic derecho → Abrir (o `xattr -dr com.apple.quarantine`). Con cuenta paga se puede notarizar en CI.

## 9. Plan de entregas (PRs chicos)

1. **Docs** (este PR).
2. Esqueleto: Swift Package, app de barra de menú vacía, login item, script de bundle, CI.
3. `MonitorCore`: CPU, memoria, red, disco, batería + tests.
4. Ping (ICMP + TCP fallback, gateway) + tests.
5. `HealthEvaluator` + ícono semáforo.
6. Popover: problemas primero, sparklines, selector de intervalo.
7. Ajustes mínimos (destinos de ping, umbrales, login item).
8. Medición de consumo y optimización; release v1.0.

Los PRs 2–4 no dependen de las preguntas abiertas y avanzan ya. El ping se construye con destinos configurables, así cambiar la lista es trivial.

## 10. Cómo trabajo de forma autónoma

- Cada PR es chico, con descripción de qué hace y cómo probarlo, y el `.app` compilado como artefacto de CI.
- No puedo correr la app en una Mac desde la nube: la verificación es compilación + tests en CI. Las pruebas visuales y de consumo reales las hacés vos (o yo, si conectás tu Mac al hilo).
- Lo que no está claro queda marcado **[PENDIENTE]** y no se construye; lo que es fácil de cambiar se decide con un **[SUPUESTO]** escrito.
