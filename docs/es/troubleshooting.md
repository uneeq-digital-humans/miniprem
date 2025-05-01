# Guía de Solución de Problemas

Esta guía proporciona soluciones para problemas comunes que podrías encontrar al ejecutar la plataforma MiniPrem.

## Pasos Generales de Solución de Problemas

1. **Verificar Estado del Servicio**:
   ```bash
   ./miniprem.sh status
   ```

2. **Ver Registros del Servicio**:
   ```bash
   ./miniprem.sh logs
   # O para un servicio específico
   ./miniprem.sh logs renny
   ```

3. **Reiniciar Servicios**:
   ```bash
   ./miniprem.sh restart
   ```

4. **Verificar Recursos de Docker**:
   ```bash
   docker stats
   ```

## Problemas con vLLM

### El Contenedor vLLM No Inicia

**Síntomas**: El contenedor vLLM se detiene inmediatamente después de iniciar

**Soluciones**:
1. Verificar disponibilidad de GPU:
   ```bash
   nvidia-smi
   ```

2. Verificar que el runtime de NVIDIA esté configurado correctamente:
   ```bash
   docker info | grep -i runtime
   ```

3. Verificar conflictos de puertos:
   ```bash
   sudo lsof -i :8000
   ```

4. Verificar registros de vLLM:
   ```bash
   docker logs vllm
   ```

### Problemas de Carga del Modelo

**Síntomas**: Mensajes de error al intentar usar el modelo

**Soluciones**:
1. Verificar si el modelo está descargado:
   ```bash
   docker exec -it vllm ls /root/.cache/huggingface
   ```

2. Volver a extraer el modelo:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model gemma-3-4b
   ```

3. Verificar memoria GPU suficiente:
   ```bash
   nvidia-smi
   ```

4. Probar un modelo más pequeño para pruebas:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

## Problemas con Flowise

### Interfaz de Flowise No Accesible

**Síntomas**: No se puede acceder a Flowise en http://localhost:3000

**Soluciones**:
1. Verificar si el contenedor está en ejecución:
   ```bash
   docker ps | grep flowise
   ```

2. Verificar registros del contenedor:
   ```bash
   docker logs flowise
   ```

3. Verificar disponibilidad del puerto:
   ```bash
   curl -I http://localhost:3000
   ```

### Fallos en la Creación de Chatflows

**Síntomas**: No se pueden crear o guardar chatflows

**Soluciones**:
1. Verificar conectividad de la base de datos:
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/database.sqlite
   ```

2. Verificar permisos de volumen:
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/
   ```

3. Intentar ejecutar el script de configuración manualmente:
   ```bash
   ./docker/setup-chatflow-post-deployment-fixed.sh
   ```

### Problemas de Autenticación de API

**Síntomas**: Errores de no autorizado al acceder a la API

**Soluciones**:
1. Verificar si estás usando la clave API correcta:
   ```
   Authorization: Bearer miniprem_demo_secret_key
   ```

2. Restablecer la clave API:
   ```bash
   docker exec -it flowise node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```
   Luego actualiza `FLOWISE_SECRETKEY_OVERWRITE` en el archivo compose apropiado (docker-compose.base.yml o docker-compose.extras.yml, dependiendo de tu tipo de instalación).

## Problemas con Renny

### Fallos en la Verificación de Salud de Renny

**Síntomas**: El contenedor Renny reporta estado no saludable

**Soluciones**:
1. Verificar registros de Renny:
   ```bash
   docker logs renny
   ```

2. Verificar conectividad con la plataforma UneeQ:
   ```bash
   curl -I $DHOP_ADDRESS
   ```

3. Verificar servicios de Audio2Face:
   ```bash
   docker ps | grep audio2face
   ```

4. Verificar archivo configuration.dat:
   ```bash
   cat docker/configuration.dat
   ```

### Problemas de Conectividad con Audio2Face

**Síntomas**: Las animaciones faciales no funcionan correctamente

**Soluciones**:
1. Verificar servicios de Audio2Face:
   ```bash
   docker logs audio2face_with_emotion
   docker logs audio2face_controller
   ```

2. Verificar configuración de red:
   ```bash
   docker exec -it renny ping audio2face-gateway
   ```

3. Verificar configuración de A2F:
   ```bash
   cat docker/a2f-config.yml
   ```

## Problemas de Monitoreo

### Prometheus No Recolecta Métricas

**Síntomas**: No hay métricas en los paneles de Grafana

**Soluciones**:
1. Verificar si Prometheus está en ejecución:
   ```bash
   docker ps | grep prometheus
   ```

2. Verificar objetivos de Prometheus:
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```

3. Verificar configuración de Prometheus:
   ```bash
   cat docker/prometheus.yml
   ```

### Problemas de Inicio de Sesión en Grafana

**Síntomas**: No se puede iniciar sesión en Grafana

**Soluciones**:
1. Usar credenciales predeterminadas (admin/admin)

2. Restablecer contraseña de administrador:
   ```bash
   docker exec -it grafana grafana-cli admin reset-admin-password admin
   ```

3. Verificar registros de Grafana:
   ```bash
   docker logs grafana
   ```

## Problemas de Red

### Conflictos de Puertos

**Síntomas**: Los servicios fallan al iniciar debido a que el puerto ya está en uso

**Soluciones**:
1. Encontrar qué proceso está usando el puerto:
   ```bash
   sudo lsof -i :PORT_NUMBER
   ```

2. Detener el proceso en conflicto o modificar el puerto en el archivo compose apropiado (docker-compose.base.yml o docker-compose.extras.yml).

3. Verificar configuración del firewall:
   ```bash
   sudo ufw status
   ```

### Problemas de Red de Docker

**Síntomas**: Los servicios no pueden comunicarse entre sí

**Soluciones**:
1. Verificar red de Docker:
   ```bash
   docker network inspect uneeq-miniprem_default
   ```

2. Verificar conectividad del contenedor:
   ```bash
   docker exec -it flowise ping vllm
   ```

3. Reiniciar Docker:
   ```bash
   sudo systemctl restart docker
   ```

## Problemas de Recursos

### Out of Memory

**Síntomas**: Los servicios se bloquean con errores de OOM

**Soluciones**:
1. Verificar uso de memoria:
   ```bash
   free -h
   docker stats
   ```

2. Incrementar espacio de intercambio del host:
   ```bash
   sudo fallocate -l 8G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

3. Ajustar límites de memoria Docker:
   ```yaml
   deploy:
     resources:
       limits:
         memory: 8G
   ```

### Problemas de Memoria GPU

**Síntomas**: Errores de memoria GPU agotada

**Soluciones**:
1. Monitorear uso de GPU:
   ```bash
   nvidia-smi -l 1
   ```

2. Usar un modelo más pequeño:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

3. Prevenir otros aplicaciones de usar la GPU durante la operación de MiniPrem

Si quieres agregar más servicios o cambiar tu tipo de instalación, vuelve a ejecutar el instalador y selecciona la opción deseada.