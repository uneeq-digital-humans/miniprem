# Registros de Contenedores

Visualiza registros en tiempo real de los contenedores que se ejecutan en la pila de MiniPrem. Esta característica te permite monitorear servicios directamente desde la documentación.

## Contenedores Disponibles

Selecciona un contenedor del menú desplegable para ver sus registros:

```container-logs
flowise
vllm
redis
prometheus
grafana
renny
log-streamer
```

## Cómo Funciona

Esta característica se conecta al servicio Log Streamer que se ejecuta en el puerto 8082, que proporciona una interfaz WebSocket a los registros de Docker. Cuando seleccionas un contenedor, se establece una conexión WebSocket a:

```
ws://localhost:8082/logs/{container-name}
```

El servicio de transmisión de registros luego se conecta a Docker y transmite los registros en tiempo real a tu navegador.

## Solución de Problemas

Si no ves los registros apareciendo:

1. Asegúrate de que el servicio log-streamer esté en ejecución:
   ```bash
   docker ps | grep log-streamer
   ```

2. Verifica los registros del servicio log-streamer:
   ```bash
   docker logs log-streamer
   ```

3. Asegúrate de que tu navegador admita WebSockets y tenga acceso a localhost:8082

4. Si los registros aún no aparecen, el servicio automáticamente recurrirá a registros simulados con fines de demostración.