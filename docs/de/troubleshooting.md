# Anleitung zur Fehlerbehebung

Dieser Leitfaden enthält Lösungen für häufige Probleme, die beim Betrieb der MiniPrem-Plattform auftreten können.

## Allgemeine Schritte zur Fehlerbehebung

1. **Dienststatus prüfen**:
   ```bash
   ./miniprem.sh status
   ```

2. **Dienstprotokolle anzeigen**:
   ```bash
   ./miniprem.sh logs
   # Or for a specific service
   ./miniprem.sh logs renny
   ```

3. **Neustart-Dienste**:
   ```bash
   ./miniprem.sh restart
   ```

4. **Docker-Ressourcen prüfen**:
   ```bash
   docker stats
   ```

## vLLM-Ausgaben

### vLLM-Container startet nicht

**Symptome**: vLLM-Container stoppt sofort nach dem Start

**Lösungen**:
1. Prüfen Sie die Verfügbarkeit der GPU:
   ```bash
   nvidia-smi
   ```

2. Vergewissern Sie sich, dass die NVIDIA-Laufzeitumgebung richtig konfiguriert ist:
   ```bash
   docker info | grep -i runtime
   ```

3. Prüfen Sie auf Anschlusskonflikte:
   ```bash
   sudo lsof -i :8000
   ```

4. Prüfen Sie die vLLM-Protokolle:
   ```bash
   docker logs vllm
   ```

### Probleme beim Laden von Modellen

**Symptome**: Fehlermeldungen beim Versuch, das Modell zu verwenden

**Lösungen**:
1. Prüfen Sie, ob das Modell heruntergeladen wurde:
   ```bash
   docker exec -it vllm ls /root/.cache/huggingface
   ```

2. Ziehen Sie das Modell erneut:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model facebook/opt-125m
   ```

3. Prüfen Sie, ob genügend GPU-Speicher vorhanden ist:
   ```bash
   nvidia-smi
   ```

4. Probieren Sie ein kleineres Modell zum Testen aus:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

## Flowise-Ausgaben

### Flowise UI nicht zugänglich

**Symptome**: Kein Zugriff auf Flowise unter http://localhost:3000

**Lösungen**:
1. Prüfen Sie, ob der Container läuft:
   ```bash
   docker ps | grep flowise
   ```

2. Prüfen Sie die Behälterprotokolle:
   ```bash
   docker logs flowise
   ```

3. Überprüfen Sie die Verfügbarkeit des Anschlusses:
   ```bash
   curl -I http://localhost:3000
   ```

### Chatflow-Erstellung fehlgeschlagen

**Symptome**: Chatabläufe können nicht erstellt oder gespeichert werden

**Lösungen**:
1. Überprüfen Sie die Datenbankkonnektivität:
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/database.sqlite
   ```

2. Prüfen Sie die Volume-Berechtigungen:
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/
   ```

3. Versuchen Sie, das Setup-Skript manuell auszuführen:
   ```bash
   ./docker/setup-chatflow-post-deployment-fixed.sh
   ```

### API-Authentifizierungsprobleme

**Symptome**: Nicht autorisierte Fehler beim Zugriff auf die API

**Lösungen**:
1. Überprüfen Sie, ob Sie den richtigen API-Schlüssel verwenden:
   ```
   Authorization: Bearer miniprem_demo_secret_key
   ```

2. Setzen Sie den API-Schlüssel zurück:
   ```bash
   docker exec -it flowise node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```
   Aktualisieren Sie dann den `FLOWISE_SECRETKEY_OVERWRITE` in der entsprechenden Compose-Datei (docker-compose.base.yml oder docker-compose.extras.yml, je nach Installationstyp).

## Renny-Probleme

### Renny Health Check Fehler

**Symptome**: Renny-Container meldet ungesunden Status

**Lösungen**:
1. Überprüfen Sie die Renny-Protokolle:
   ```bash
   docker logs renny
   ```

2. Überprüfen Sie die Konnektivität der UneeQ-Plattform:
   ```bash
   curl -I $DHOP_ADDRESS
   ```

3. Überprüfen Sie die Audio2Face-Dienste:
   ```bash
   docker ps | grep audio2face
   ```

4. Überprüfen Sie die Datei configuration.dat:
   ```bash
   cat docker/configuration.dat
   ```

### Audio2Face Verbindungsprobleme

**Symptome**: Gesichtsanimationen funktionieren nicht richtig

**Lösungen**:
1. Überprüfen Sie die Audio2Face-Dienste:
   ```bash
   docker logs audio2face_with_emotion
   docker logs audio2face_controller
   ```

2. Überprüfen Sie die Netzwerkkonfiguration:
   ```bash
   docker exec -it renny ping audio2face-gateway
   ```

3. Prüfen Sie die A2F-Konfiguration:
   ```bash
   cat docker/a2f-config.yml
   ```

## Probleme bei der Überwachung

### Prometheus sammelt keine Metriken

**Symptome**: Keine Metriken in Grafana Dashboards

**Lösungen**:
1. Prüfen Sie, ob Prometheus läuft:
   ```bash
   docker ps | grep prometheus
   ```

2. Überprüfen Sie die Prometheus-Ziele:
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```

3. Überprüfen Sie die Prometheus-Konfiguration:
   ```bash
   cat docker/prometheus.yml
   ```

### Grafana Login-Probleme

**Symptome**: Kann sich nicht bei Grafana anmelden

**Lösungen**:
1. Standard-Anmeldedaten verwenden (admin/admin)

2. Admin-Passwort zurücksetzen:
   ```bash
   docker exec -it grafana grafana-cli admin reset-admin-password admin
   ```

3. Prüfen Sie die Grafana-Protokolle:
   ```bash
   docker logs grafana
   ```

## Netzwerk-Probleme

### Port-Konflikte

**Symptome**: Dienste können nicht gestartet werden, weil der Port bereits verwendet wird

**Lösungen**:
1. Finden Sie heraus, welcher Prozess den Port verwendet:
   ```bash
   sudo lsof -i :PORT_NUMBER
   ```

2. Beenden Sie den Konfliktprozess oder ändern Sie den Port in der entsprechenden Compose-Datei (docker-compose.base.yml oder docker-compose.extras.yml).

3. Überprüfen Sie die Firewall-Einstellungen:
   ```bash
   sudo ufw status
   ```

### Docker Netzwerkprobleme

**Symptome**: Dienste können nicht miteinander kommunizieren

**Lösungen**:
1. Überprüfen Sie das Docker-Netzwerk:
   ```bash
   docker network inspect uneeq-miniprem_default
   ```

2. Überprüfen Sie die Konnektivität des Containers:
   ```bash
   docker exec -it flowise ping vllm
   ```

3. Starten Sie Docker neu:
   ```bash
   sudo systemctl restart docker
   ```

## Ressourcenproblematik

## Kein Speicherplatz vorhanden

**Symptome**: Dienste stürzen mit OOM-Fehlern ab

**Lösungen**:
1. Überprüfen Sie die Speichernutzung:
   ```bash
   free -h
   docker stats
   ```

2. Erhöhen Sie den Swap-Bereich des Hosts:
   ```bash
   sudo fallocate -l 8G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

3. Passen Sie die Speichergrenzen von Docker an:
   ```yaml
   deploy:
     resources:
       limits:
         memory: 8G
   ```

### GPU-Speicher-Probleme

**Symptome**: GPU-Fehler wegen Speichermangels

**Lösungen**:
1. Überwachen Sie die GPU-Auslastung:
   ```bash
   nvidia-smi -l 1
   ```

2. Verwenden Sie ein kleineres Modell:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

3. Verhindern, dass andere Anwendungen die GPU während des MiniPrem-Betriebs nutzen

Wenn Sie weitere Dienste hinzufügen oder den Installationstyp ändern möchten, führen Sie das Installationsprogramm erneut aus und wählen Sie die gewünschte Option.