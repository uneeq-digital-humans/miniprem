# Renny Digital Human

Dieser Leitfaden behandelt die Renny Digital Human-Komponente der MiniPrem-Plattform, die die visuelle Schnittstelle für menschenähnliche Interaktionen bietet.

## Überblick

Renny ist ein digitaler menschlicher Avatar, der auf der Technologie von UneeQ basiert und eine visuelle Schnittstelle für KI-Interaktionen bietet. Er kombiniert Gesichtsanimationen, Lippensynchronisation und Gestenfunktionen, um ein ansprechendes Gesprächserlebnis zu schaffen.

## Zugriff auf Renny

- **Gesundheitsendpunkt**: http://localhost:8081/health
- **Containername**: `renny`

## Architektur

Die Komponente Renny interagiert mit mehreren anderen Diensten:

1. **Audio2Face Integration**: Konvertiert Audio in Gesichtsanimationen
2. **UneeQ-Plattform**: Verwaltet das digitale menschliche Rendering
3. **Azure Speech Services**: Bietet Text-to-Speech-Funktionen

## Konfiguration

### Hauptkonfigurationsdatei

Die Hauptkonfiguration für Renny wird in der Datei `docker/configuration.dat` gespeichert, die Folgendes enthält:

- **Server**: Der Endpunkt des UneeQ-Servers
- TenantId**: Ihre UneeQ-Mieterkennung
- **JWSSecret**: Authentifizierungstoken für UneeQ-Dienste

### Umgebungsvariablen

Wichtige Umgebungsvariablen in `docker/docker-compose.env`:

- **A2F_ADDRESS**: Audio2Face-Dienstadresse
- **DHOP_ADDRESS**: UneeQ-Plattform-Adresse
- **DHOP_APIKEY**: UneeQ-Plattform-API-Schlüssel
- **DHOP_TENANTID**: UneeQ-Mieter-ID
- **AZURE_REGION**: Azure-Region für Sprachdienste
- **AZURE_SPEECH**: Azure-Sprachdienstschlüssel

## Gesundheitsüberwachung

Sie können den Gesundheitszustand von Renny mit überprüfen:

```bash
curl -f http://localhost:8081/health
```

Dieser Endpunkt liefert Informationen über den aktuellen Zustand des Dienstes und die Verbindungen zu abhängigen Diensten.

## Netzwerk-Konfiguration

Renny verwendet den Host-Netzwerkmodus, um eine optimale Leistung zu gewährleisten:

```yaml
network_mode: "host"
```

Dadurch kann Renny direkt auf die Netzwerkschnittstellen des Systems zugreifen, ohne dass das Docker-Netzwerk isoliert wird.

## GPU-Beschleunigung

Renny nutzt die NVIDIA-GPU-Beschleunigung für das Rendering:

```yaml
runtime: nvidia
```

Dies gewährleistet eine flüssige Animation und Mimik.

## Integration mit LLM

Die Integration zwischen Renny und dem LLM (über Flowise) funktioniert wie folgt:

1. Die Benutzereingabe wird erfasst (Text oder Audio)
2. Die Eingabe wird von der Flowise/vLLM-Pipeline verarbeitet
3. Die Antwort wird über Azure TTS in Sprache umgewandelt
4. Audio2Face erzeugt mit der Sprache synchronisierte Gesichtsanimationen
5. Renny rendert den animierten Avatar, der die Antwort spricht

## Erweiterte Anpassung

### Rendering-Optionen

Renny unterstützt verschiedene Rendering-Konfigurationen über Kommandozeilenparameter:

```
-RenderOffScreen  # Headless rendering
-ResX=1920        # Horizontal resolution
-ResY=1080        # Vertical resolution
```

Für die grafische Anzeige (statt headless) können Sie die Docker-Konfiguration ändern:

```yaml
# Uncomment for visual rendering
environment:
  - DISPLAY=$DISPLAY
volumes:
  - /tmp/.X11-unix:/tmp/.X11-unix
  - ~/.Xauthority:/home/ue4/.Xauthority
```

### Animationseinstellungen

Die Audio2Face-Animationsparameter können in den A2F-Konfigurationsdateien eingestellt werden:

- **Lippensynchronisation**: Steuert die Genauigkeit der Mundbewegung
- Ausdrucksintensität**: Passt die Stärke der Gesichtsausdrücke an
- **Blinzelparameter**: Steuert die Häufigkeit und Art des Augenblinzelns

## Fehlersuche

### Allgemeine Probleme

1. **Keine visuelle Ausgabe**:
   - Prüfen Sie, ob `-RenderOffScreen` aktiviert ist
   - Überprüfen Sie GPU-Treiber und Rendering-Fähigkeiten

2. **Schlechte Animationsqualität**:
   - Status des A2F-Dienstes prüfen
   - Überprüfen Sie die Audioqualität und -verarbeitung

3. **Verbindungsprobleme**:
   - Überprüfen Sie die Konnektivität der UneeQ-Plattform
   - Überprüfen Sie die Netzwerkeinstellungen und Firewall-Regeln

4. **Audio-visuelle Synchronisationsprobleme**:
   - Parameter "A2F_AUDIO_DELAY_TIME_MS" anpassen
   - Prüfen Sie die Systemleistung auf Rendering-Verzögerungen