# Flowise Konfigurationshandbuch

Flowise bietet eine visuelle Schnittstelle für die Erstellung und Verwaltung von AI-Workflows. Dieser Leitfaden hilft Ihnen bei der Einrichtung und Verwendung von Flowise mit vLLM-Integration.

## Zugriff auf Flowise

- **URL**: http://localhost:3000
- **Standard-Anmeldeinformationen**:
  - Benutzername: `Benutzer`
  - Passwort: `Passwort`

## Flowise-Konzepte

- **Chatflows**: Visuelle Darstellungen von Konversationsabläufen
- **Knoten**: Komponenten, die bestimmte Funktionen ausführen (Prompts, Modelle, Speicher, etc.)
- **Kanten**: Verbindungen zwischen Knoten, die den Datenfluss definieren
- API**: RESTful-Endpunkte zur programmatischen Interaktion mit Ihren Chatflows

## Erstellen eines Chatablaufs mit vLLM

### 1. Zugang zur Flowise UI

1. Öffnen Sie Ihren Browser und navigieren Sie zu: http://localhost:3000
2. Melden Sie sich mit dem Benutzernamen `Benutzer` und dem Passwort `Passwort` an.

### 2. Erstellen Sie einen neuen Chatablauf

1. Klicken Sie in der Seitenleiste auf "Chatflows".
2. Klicken Sie auf die Schaltfläche "+", um einen neuen Chatflow zu erstellen
3. Benennen Sie Ihren Chatflow (z. B. "vLLM Gemma3 Chatflow")

### 3. Knoten hinzufügen und konfigurieren

#### System-Prompt-Knoten

1. Ziehen Sie im Knotenbedienfeld einen "System Prompt"-Knoten auf die Arbeitsfläche und legen Sie ihn dort ab.
2. Konfigurieren Sie den Knoten mit:
   - Eingabeaufforderung: "Sie sind ein hilfreicher Assistent, der von Gemma3 unterstützt wird. Geben Sie prägnante und genaue Antworten."

#### vLLM-Knoten

1. Ziehen Sie im Knotenbedienfeld einen "vLLM"- oder "OpenAI-kompatiblen" Knoten auf die Leinwand
2. Konfigurieren Sie den Knoten mit:
   - Basis-URL: `http://vllm:8000/v1` (verwenden Sie den Namen des Docker-Containers, nicht localhost)
   - Modell: `gemma-3-4b`
   - Temperatur: `0.7`
   - Maximale Token: `1000`
   - Andere Einstellungen auf den Standardwerten belassen

#### Pufferspeicher-Knoten

1. Ziehen Sie im Knotenbedienfeld einen Knoten "Pufferspeicher" auf die Arbeitsfläche und lassen Sie ihn dort fallen
2. Konfigurieren Sie den Knoten mit:
   - Speicher Schlüssel: Chat_History
   - Meldungen zurückgeben: `true` (angekreuzt)
   - Max Token Limit: `2000`

#### Konversationskettenknoten

1. Ziehen Sie aus dem Knoten-Panel einen "Conversation Chain"-Knoten auf die Leinwand
2. Keine zusätzliche Konfiguration erforderlich

#### Chat-Auslöser-Knoten

1. Ziehen Sie aus dem Knoten-Panel einen "Chat-Trigger"-Knoten auf die Leinwand
2. Keine zusätzliche Konfiguration erforderlich

### 4. Verbinden Sie die Knoten

Verbinden Sie die Knotenpunkte mit den folgenden Verbindungen:

1. System-Prompt → Gesprächskette (von "prompt" zu "systemPrompt")
2. vLLM → Gesprächskette (von "model" zu "llm")
3. Pufferspeicher → Konversationskette (von "memory" zu "memory")
4. Gesprächskette → Chat-Trigger (von "output" nach "input")

### 5. Speichern und Testen

1. Klicken Sie auf die Schaltfläche "Speichern" oben rechts
2. Klicken Sie auf die Schaltfläche "Chat", um Ihren Chatablauf zu testen

## Verwendung der Flowise API

Sie können mit Ihrem Chatflow über die Flowise-API interagieren.

### Authentifizierung

Fügen Sie den folgenden Header zu Ihren API-Anfragen hinzu:
```
  "Authorization: Bearer YOUR_DEFAULT_TOKEN_HERE"
```