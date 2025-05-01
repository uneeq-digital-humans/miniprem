# Container-Protokolle

Zeigen Sie Echtzeit-Protokolle von Containern an, die im MiniPrem-Stack ausgeführt werden. Mit dieser Funktion können Sie Dienste direkt aus der Dokumentation überwachen.

## Verfügbare Container

Wählen Sie einen Container aus der Dropdown-Liste, um dessen Protokolle anzuzeigen:

```container-logs
flowise
vllm
redis
prometheus
grafana
renny
log-streamer
```

## Funktionsweise

Diese Funktion stellt eine Verbindung zum Log Streamer-Dienst her, der auf Port 8082 läuft und eine WebSocket-Schnittstelle zu den Docker-Protokollen bereitstellt. Wenn Sie einen Container auswählen, wird eine WebSocket-Verbindung hergestellt zu:

```
ws://localhost:8082/logs/{container-name}
```

Der Log Streamer-Dienst verbindet sich dann mit Docker und streamt Protokolle in Echtzeit in Ihren Browser.

## Fehlerbehebung

Wenn Sie keine Protokolle sehen:

1. Stellen Sie sicher, dass der log-streamer-Dienst läuft:
   ```bash
   docker ps | grep log-streamer
   ```

2. Überprüfen Sie die Protokolle des log-streamer-Dienstes:
   ```bash
   docker logs log-streamer
   ```

3. Stellen Sie sicher, dass Ihr Browser WebSockets unterstützt und Zugriff auf localhost:8082 hat

4. Wenn Protokolle immer noch nicht erscheinen, fällt der Dienst automatisch auf simulierte Protokolle für Demonstrationszwecke zurück.