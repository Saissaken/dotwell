# Requisitos — Mac Resource Monitor

Estado: **borrador v0.1** (2026-11-26). Las secciones marcadas **[SUPUESTO]** son decisiones mías por defecto, fáciles de cambiar. Las marcadas **[PENDIENTE]** esperan confirmación de Cabezon y no se construyen hasta tenerla.

## 1. Objetivo

Una app nativa de macOS que vive en la barra de menú, siempre abierta, que muestra de un vistazo si la máquina está bien y, al hacer clic, gráficos simples de los recursos críticos. El uso principal es **mirar el ping**.

## 2. Prioridad absoluta: bajo consumo

Si una funcionalidad compite con el consumo, gana el consumo. Presupuesto objetivo (medido en un Apple Silicon, popover cerrado):

| Métrica | Objetivo |
|---|---|
| CPU promedio | < 0,2 % de un núcleo |
| Memoria (RSS) | < 25 MB |
| Wakeups por segundo | < 2 |
| "Impacto energético" en Monitor de Actividad | Bajo / ~0 |
| Tamaño del .app | < 5 MB |

Con el popover abierto se permite más (redibujar gráficos), pero vuelve al presupuesto al cerrarlo. Cada release mide estos números y los anota en el PR.

## 3. Funcionalidades

### 3.1 Siempre corriendo
- R1. Ícono en el sector derecho de la barra de menú. Sin ícono en el Dock ni ventana principal.
- R2. Inicia con la sesión (login item), activado por defecto, con opción para desactivarlo.
- R3. Si se cierra inesperadamente, no hace falta que se relance sola en v1 **[SUPUESTO]**.

### 3.2 Ícono tipo semáforo
- R4. El ícono indica el estado general: verde (todo bien), amarillo (algo para mirar), rojo (problema).
- R5. Estilo Apple: ícono monocromo que respeta modo claro/oscuro, con un **puntito de color** como indicador. **[PENDIENTE: variante, ver §6]**
- R6. El estado es el peor de todas las métricas, con histéresis para que no parpadee (tiene que sostenerse unos segundos antes de cambiar).

### 3.3 Popover
- R7. Al hacer clic se abre un popover con estilo nativo de macOS (material translúcido, tipografía del sistema, gráficos minimalistas).
- R8. **Problemas primero:** las métricas en amarillo/rojo aparecen arriba, en una sección separada.
- R9. **Sin scroll:** todo entra en una sola vista de tamaño fijo.
- R10. Intervalo por defecto: últimos 30 s. Selector de intervalo: 30 s · 5 min · 1 h **[SUPUESTO]**.
- R11. Cada métrica muestra el número actual grande + gráfico chico (sparkline).

### 3.4 Métricas v1

| # | Métrica | Qué se muestra |
|---|---|---|
| M1 | **Ping** (principal) | Latencia en ms, pérdida de paquetes %, jitter. Varios destinos. **[PENDIENTE: destinos]** |
| M2 | CPU | % total usado |
| M3 | Memoria | GB usados / total + **presión de memoria** del sistema (la que usa macOS; el % usado engaña porque macOS usa toda la RAM como caché) |
| M4 | Disco | Espacio libre (GB y %) + lectura/escritura MB/s **[SUPUESTO]** |
| M5 | Batería | Consumo en **watts** (descarga en batería, o entrada del cargador si está enchufada). El % no se repite porque ya lo muestra macOS. **[PENDIENTE: confirmar]** |
| M6 | Red | Bajada y subida en Mbps |

### 3.5 Métricas extra recomendadas **[PENDIENTE: elegir]**
- E1. Estado térmico (si macOS está bajando el rendimiento por temperatura). Casi gratis de medir.
- E2. Top 3 procesos por CPU (solo calculado con el popover abierto, para no gastar).
- E3. Ventiladores RPM (solo en Macs con ventilador; requiere leer SMC).
- E4. Destino de ping/IP pública/nombre de la red Wi‑Fi y calidad de señal.

## 4. Umbrales por defecto del semáforo **[SUPUESTO, ajustables]**

| Métrica | Amarillo | Rojo |
|---|---|---|
| Ping (destino principal) | > 80 ms o pérdida > 2 % (10 s) | > 200 ms, pérdida > 10 %, o sin respuesta |
| CPU | > 80 % sostenido 30 s | > 95 % sostenido 60 s |
| Memoria | presión "warning" | presión "critical" |
| Disco | < 15 % libre | < 5 % libre |
| Batería | consumo > 25 W en batería | — |
| Térmico (si se incluye) | "serious" | "critical" |

## 5. Fuera de alcance v1
- Notificaciones push, alertas sonoras.
- Exportar datos, historial más largo que 1 h, persistir historial entre reinicios.
- App Store (el sandbox complica ping ICMP y lectura de batería).
- Ajustes complejos: v1 trae una pantalla mínima (destinos de ping, login item, umbrales).

## 6. Preguntas abiertas
Ver la tarjeta de decisión en el hilo del proyecto. Se registran acá las respuestas:

- Q1. Destinos de ping: —
- Q2. Batería: watts vs tiempo restante: —
- Q3. Variante del ícono: —
- Q4. Métricas extra: —
- Q5. Distribución (¿tenés cuenta de Apple Developer paga para firmar/notarizar?): —
- Q6. Mac y macOS (chip, versión): —
