# Monitoreo con Prometheus y Grafana

Esta guía cubre cómo usar las herramientas de monitoreo integradas para rastrear métricas de rendimiento y uso de tu plataforma MiniPrem.

## Descripción General

MiniPrem incluye dos potentes herramientas de monitoreo:

1. **Prometheus**: Una base de datos de series temporales que recopila y almacena métricas
2. **Grafana**: Una plataforma de visualización que crea paneles a partir de los datos de Prometheus

## Acceso a las Herramientas de Monitoreo

| Herramienta | URL | Credenciales Predeterminadas |
|------------|-----|------------------------------|
| Grafana | http://localhost:3001 | admin / admin |
| Prometheus | http://localhost:9090 | N/A |

## Paneles de Grafana

### Paneles Preconfigurados

La instalación de MiniPrem incluye un panel preconfigurado para monitorear Flowise:

1. **Panel de Flowise**: Muestra métricas clave para tu instancia de Flowise:
   - Conteo de Solicitudes HTTP
   - Duración de Solicitudes HTTP
   - Uso de Memoria
   - Uso de CPU

### Ver Paneles

1. Inicia sesión en Grafana en http://localhost:3001
2. Haz clic en "Dashboards" en la barra lateral izquierda
3. Selecciona "Flowise Dashboard" de la lista

### Crear Paneles Personalizados

1. Haz clic en el icono "+" en la barra lateral
2. Selecciona "Dashboard"
3. Haz clic en "Add new panel"
4. Elige tu tipo de visualización (gráfico, indicador, tabla, etc.)
5. Ingresa una consulta de Prometheus en el editor de consultas
6. Configura las opciones de visualización
7. Haz clic en "Save" para agregar el panel a tu dashboard

## Ejemplos de Consultas de Prometheus

### Métricas Básicas

```promql
# Conteo de solicitudes HTTP
http_request_total

# Duración promedio de solicitudes en los últimos 5 minutos
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# Uso de memoria
process_resident_memory_bytes

# Uso de CPU
rate(process_cpu_seconds_total[1m])
```
