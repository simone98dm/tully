# MyMenu — Design Spec

**Data:** 2026-05-24  
**Target:** macOS 13 Ventura+  
**Stack:** Swift 5.9+, SwiftUI + AppKit, nessun framework terze parti  
**Distribuzione:** non firmata, non App Store

---

## Scope

App menu bar macOS con due moduli:

1. **System Monitor** — CPU, RAM, disco, processi top, banda di rete
2. **Window Manager** — shortcut globali configurabili per spostare finestre in zone predefinite

Monitor Dimming: fuori scope.

---

## Architettura Generale

### Entry point & lifecycle

`MyMenuApp.swift` usa `@NSApplicationDelegateAdaptor(AppDelegate.self)` con `body` vuoto (`Settings {}`). Tutto il lifecycle vive in `AppDelegate`.

`AppDelegate` possiede:
- `NSStatusItem` con icona SF Symbol `"menubar.rectangle"`
- `NSPopover` con `contentViewController = NSHostingController(rootView: ContentView())`
- Click su status item → toggle `show/close` popover ancorato all'item

### Struttura servizi

Ogni modulo espone un `@MainActor final class` singleton `@Observable`. Le view SwiftUI leggono stato direttamente. I servizi con lavoro pesante girano su thread dedicati e proiettano output su main actor via `Task { @MainActor in ... }`.

### Layout popover

`TabView` con `.tabViewStyle(.automatic)` — due tab:

| Tab | Icona SF | View |
|-----|----------|------|
| System | `cpu` | `SystemMonitorView` |
| Windows | `rectangle.3.group` | `WindowManagerView` |

### Persistenza

`UserDefaults` per shortcuts configurati. Nessun Core Data.

### Info.plist

```
LSUIElement = YES
```

Nessun sandbox, nessun entitlement App Store.

---

## Modulo 1: System Monitor

### File

```
Modules/SystemMonitor/
├── SystemMonitorService.swift
├── DiskScanService.swift
└── SystemMonitorView.swift
```

### Metriche (aggiornamento ogni 2s)

| Metrica | API |
|---------|-----|
| CPU % | `host_processor_info()` → delta tick |
| RAM used/total | `vm_statistics64_data_t` |
| Disco used/free/total | `FileManager.attributesOfFileSystem(forPath: "/")` |
| Rete ↑↓ bytes/s | `getifaddrs()` → delta `ifi_ibytes`/`ifi_obytes` su interfacce fisiche (escluse loopback/utun) |
| Top-5 processi CPU | `proc_listallpids()` + `proc_pidinfo(PROC_PIDTASKINFO)` |
| Top-5 processi RAM | stessa chiamata, ordinamento diverso |

### Threading

`SystemMonitorService` lancia un `Timer` ogni 2s su `DispatchQueue.global(qos: .utility)`. Calcola delta, proietta risultati su `@MainActor`.

### Modello dati

```swift
struct SystemSnapshot {
    var cpuPercent: Double
    var ramUsed: UInt64
    var ramTotal: UInt64
    var diskUsed: Int64
    var diskTotal: Int64
    var netIn: Double   // bytes/s
    var netOut: Double  // bytes/s
    var topCPU: [ProcessInfo]
    var topRAM: [ProcessInfo]
}

struct ProcessInfo: Identifiable {
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var ramBytes: UInt64
}
```

### Large Folders (sottopannello disco)

- Scan asincrono di `~` via `Process` + `du -sk` su ogni cartella top-level
- Mostra top-10 cartelle per dimensione con barra proporzionale
- Primo scan automatico all'avvio app
- Pulsante **"Rescan"** con timestamp ultimo scan; disabilitato durante scan attivo (spinner + "Scanning…")
- Cartella cliccabile → `NSWorkspace.open(url)` apre in Finder
- Cartelle senza permesso → skippate silenziosamente (`du` ritorna errore, ignorato)

### Edge cases

- PID sparisce tra campionamenti → `proc_pidinfo` ritorna errore, ignorato
- Interfaccia di rete down → byte counter a 0, nessun crash
- Counter di rete wraparound → delta negativo rilevato, campione scartato

---

## Modulo 2: Window Manager

### File

```
Modules/WindowManager/
├── WindowManagerService.swift
├── KeyboardShortcutHandler.swift
└── WindowManagerView.swift
```

### Zone predefinite (12 layout)

| Nome | x% | y% | w% | h% |
|------|----|----|----|----|
| Left Half | 0 | 0 | 50 | 100 |
| Right Half | 50 | 0 | 50 | 100 |
| Left ⅓ | 0 | 0 | 33 | 100 |
| Center ⅓ | 33 | 0 | 33 | 100 |
| Right ⅓ | 66 | 0 | 33 | 100 |
| Left ⅔ | 0 | 0 | 66 | 100 |
| Right ⅔ | 33 | 0 | 66 | 100 |
| Fullscreen | 0 | 0 | 100 | 100 |
| Top-Left | 0 | 50 | 50 | 50 |
| Top-Right | 50 | 50 | 50 | 50 |
| Bottom-Left | 0 | 0 | 50 | 50 |
| Bottom-Right | 50 | 0 | 50 | 50 |

Frame calcolato su `NSScreen.visibleFrame` della finestra target (esclude menu bar e Dock). Flip Y gestito nella conversione coordinate AX.

### Spostamento finestre

```
AXUIElementCreateSystemWide()
  → app frontmost → finestra frontmost
  → AXUIElementSetAttributeValue(kAXPositionAttribute)
  → AXUIElementSetAttributeValue(kAXSizeAttribute)
```

### Shortcut globali

`CGEventTap` su `CGEventType.keyDown`, thread dedicato con `CFRunLoop`. Match `CGEventFlags` + `keyCode` contro dizionario `[ShortcutBinding: WindowZone]` da `UserDefaults`. Match → movimento finestra su `@MainActor`.

### UI configurazione shortcut

Lista zona + campo shortcut per riga. Click campo → `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` cattura prossima combo → salva come `ShortcutBinding`. Conflitti (stessa combo, due zone) evidenziati in rosso con tooltip. Default: nessun shortcut (utente configura da zero).

### Permessi Accessibility

```
AppDelegate.applicationDidFinishLaunching
  └─ AXIsProcessTrusted() == false
       └─ WindowManagerService.isPermissionGranted = false
            └─ WindowManagerView → PermissionView
                 └─ Bottone "Apri Impostazioni Sistema"
                      └─ NSWorkspace.open(
                           "x-apple.systempreferences:
                            com.apple.preference.security?Privacy_Accessibility")
```

Pattern standard: l'utente riapre l'app dopo aver concesso il permesso. Nessun polling.

### Edge cases

- Accessibility non concessa → `WindowManagerView` mostra solo `PermissionView`
- Finestra target non supporta AX resize → errore silenzioso, nessun crash
- Multi-monitor → usa screen della finestra frontmost, non `NSScreen.main`

---

## Struttura file progetto

```
tully/
├── MyMenuApp.swift
├── AppDelegate.swift
├── ContentView.swift
├── Modules/
│   ├── SystemMonitor/
│   │   ├── SystemMonitorService.swift
│   │   ├── DiskScanService.swift
│   │   └── SystemMonitorView.swift
│   └── WindowManager/
│       ├── WindowManagerService.swift
│       ├── KeyboardShortcutHandler.swift
│       └── WindowManagerView.swift
└── Shared/
    ├── PermissionView.swift
    └── Extensions.swift
```

---

## Dipendenze tra moduli

```
AppDelegate
  ├── SystemMonitorService (indipendente, avvio immediato)
  └── WindowManagerService (avvio solo se AXIsProcessTrusted())
        └── KeyboardShortcutHandler (init dentro WindowManagerService)
```

`SystemMonitor` e `WindowManager` sono completamente indipendenti tra loro.

---

## Complessità stimata

| Componente | Complessità |
|---|---|
| AppDelegate + NSPopover + StatusItem | 2/5 |
| SystemMonitorService (CPU/RAM/disco/rete) | 3/5 |
| DiskScanService (du + top folders) | 2/5 |
| SystemMonitorView | 2/5 |
| WindowManagerService (AX + zone) | 3/5 |
| KeyboardShortcutHandler (CGEventTap) | 4/5 |
| WindowManagerView (shortcut recording) | 3/5 |
| PermissionView + flow | 1/5 |

---

## Ordine di implementazione consigliato

1. `AppDelegate` + `NSStatusItem` + `NSPopover` vuoto
2. `ContentView` con `TabView` (placeholder view per ogni tab)
3. `SystemMonitorService` + metriche base (CPU, RAM, disco, rete)
4. `SystemMonitorView`
5. `DiskScanService` + pannello Large Folders
6. `PermissionView`
7. `WindowManagerService` (AX + zone)
8. `KeyboardShortcutHandler` (CGEventTap)
9. `WindowManagerView` (lista shortcut + recording)
