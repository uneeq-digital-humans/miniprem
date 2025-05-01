# Registros de Contenedores en Vivo

Visualiza los registros en vivo de varios servicios en la pila de MiniPrem.

## Registros de Contenedores

Selecciona un servicio del menú desplegable para ver sus registros:

```terminal
```container-logs
flowise
vllm
redis
prometheus
grafana
uneeq
```

## Cómo Funciona

El terminal anterior se conecta a los registros del contenedor Docker para cada servicio. Esto te permite:

1. Depurar problemas en tiempo real
2. Monitorear la actividad de la aplicación
3. Rastrear el rendimiento del sistema

## Recolección de Registros

Los registros se recopilan usando el sistema de registro de Docker y se transmiten a esta interfaz. En un entorno de producción, podrías considerar soluciones de registro más robustas como:

- Stack ELK (Elasticsearch, Logstash, Kibana)
- Loki (parte del stack de Grafana)
- Datadog u otras soluciones de monitoreo en la nube