// Function to create an interactive API endpoint component
function createApiEndpoint(method, path, baseUrl, requestBody = null) {
  const id = 'api-' + Math.random().toString(36).substring(2, 11);
  const requestBodyId = 'req-body-' + id;
  const responseId = 'response-' + id;

  let html = `
      <div class="api-endpoint" id="${id}">
        <div class="api-header">
          <span class="api-method method-${method.toLowerCase()}">${method}</span>
          <div class="api-url-wrapper">
            <span class="api-base-url">${baseUrl}</span>
            <span class="api-url-path">${path}</span>
          </div>
          <button class="api-try-btn" onclick="sendApiRequest('${id}', '${method}', '${baseUrl}', '${path}', ${requestBody ? `'${requestBodyId}'` : 'null'})">Try it</button>
        </div>`;

  if (requestBody) {
    html += `
        <div class="api-request-body">
          <textarea id="${requestBodyId}">${JSON.stringify(requestBody, null, 2)}</textarea>
        </div>`;
  }

  html += `
      <div class="api-response-container">
        <div class="api-response-header">
          <span>Response</span>
          <span id="status-${id}"></span>
        </div>
        <div class="api-response-body" id="${responseId}">
          <em>Click "Try it" to send the request</em>
        </div>
      </div>
    </div>`;

  return html;
}

// Function to send API request
async function sendApiRequest(id, method, baseUrl, path, bodyElementId) {
  const responseElement = document.getElementById('response-' + id);
  const statusElement = document.getElementById('status-' + id);
  responseElement.innerHTML = '<em>Loading...</em>';
  statusElement.innerHTML = '';

  try {
    const options = {
      method: method,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }
    };

    if (bodyElementId) {
      const bodyElement = document.getElementById(bodyElementId);
      if (bodyElement) {
        try {
          const bodyJson = JSON.parse(bodyElement.value);
          options.body = JSON.stringify(bodyJson);
        } catch (e) {
          responseElement.innerHTML = `<pre class="log-error">Error parsing JSON: ${e.message}</pre>`;
          statusElement.innerHTML = '<span class="api-status status-error">Error</span>';
          return;
        }
      }
    }

    const fullUrl = baseUrl + path;
    const response = await fetch(fullUrl, options);
    const contentType = response.headers.get('content-type');

    let data;
    if (contentType && contentType.includes('application/json')) {
      data = await response.json();
      responseElement.innerHTML = `<pre>${JSON.stringify(data, null, 2)}</pre>`;
    } else {
      data = await response.text();
      responseElement.innerHTML = `<pre>${data}</pre>`;
    }

    if (response.ok) {
      statusElement.innerHTML = `<span class="api-status status-success">${response.status} ${response.statusText}</span>`;
    } else {
      statusElement.innerHTML = `<span class="api-status status-error">${response.status} ${response.statusText}</span>`;
    }
  } catch (error) {
    responseElement.innerHTML = `<pre class="log-error">Error: ${error.message}</pre>`;
    statusElement.innerHTML = '<span class="api-status status-error">Error</span>';
  }
}

// Function to connect to container logs
let logWebSocket = null;

function connectToContainerLogs(containerId, outputElementId) {
  const outputElement = document.getElementById(outputElementId);
  outputElement.innerHTML = '<em>Connecting to logs...</em>';

  // Close any existing connection
  if (logWebSocket && logWebSocket.readyState !== WebSocket.CLOSED) {
    logWebSocket.close();
  }

  try {
    // Connect to log service (this assumes you have a WebSocket server that streams container logs)
    // You'll need to implement this log server separately or use an existing solution
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${wsProtocol}//${window.location.hostname}:8082/logs/${containerId}`;

    logWebSocket = new WebSocket(wsUrl);

    logWebSocket.onopen = function () {
      outputElement.innerHTML = '<em>Connected. Waiting for logs...</em>';
    };

    logWebSocket.onmessage = function (event) {
      // If first message, clear the waiting text
      if (outputElement.innerHTML.includes('Waiting for logs')) {
        outputElement.innerHTML = '';
      }

      const logLine = document.createElement('div');
      logLine.className = 'terminal-line';

      // Colorize logs based on content
      const logText = event.data;
      if (logText.includes('ERROR') || logText.includes('error')) {
        logLine.classList.add('log-error');
      } else if (logText.includes('WARN') || logText.includes('warn')) {
        logLine.classList.add('log-warn');
      } else if (logText.includes('INFO') || logText.includes('info')) {
        logLine.classList.add('log-info');
      } else if (logText.includes('DEBUG') || logText.includes('debug')) {
        logLine.classList.add('log-debug');
      }

      logLine.textContent = logText;
      outputElement.appendChild(logLine);

      // Auto-scroll to bottom
      outputElement.scrollTop = outputElement.scrollHeight;
    };

    logWebSocket.onclose = function () {
      outputElement.innerHTML += '\n<em class="log-warn">Connection closed</em>';
    };

    logWebSocket.onerror = function (error) {
      outputElement.innerHTML = `<em class="log-error">Error connecting to logs: ${error.message || 'Failed to connect to log service'}</em>

        Troubleshooting Steps:
        1. Check if log-streamer is running:
          docker ps | grep log-streamer

        2. If not running, start your services:
          ./miniprem.sh start

        3. Verify log-streamer is accessible:
          Open http://localhost:8082/health in your browser

        4. Check log-streamer container logs:
          docker logs log-streamer

        Using simulated logs for demonstration purposes...
        `;

      // For development, provide fallback simulated logs
      simulateContainerLogs(containerId, outputElementId);
    };
  } catch (error) {
    outputElement.innerHTML = `<em class="log-error">Error: ${error.message}</em>`;

    // For development, provide fallback simulated logs
    simulateContainerLogs(containerId, outputElementId);
  }
}

// Function to simulate container logs for development
function simulateContainerLogs(containerId, outputElementId) {
  const outputElement = document.getElementById(outputElementId);
  outputElement.innerHTML += '\n<em class="log-warn">Using simulated logs for development</em>\n';

  const logData = {
    flowise: [
      'INFO: Flowise server started on port 3000',
      'INFO: Connected to database',
      'DEBUG: Loading predefined workflows',
      'INFO: Workflow "Basic Conversation" loaded',
      'INFO: API endpoints initialized',
      'DEBUG: Running health check on LLM connections',
      'INFO: All systems operational'
    ],
    ollama: [
      'INFO: Ollama server listening on :11434',
      'INFO: Loaded model: HuggingFaceH4/zephyr-7b-beta',
      'DEBUG: CUDA device initialized',
      'INFO: Ready for inference',
      'DEBUG: Temperature set to 0.7',
      'DEBUG: Context window: 4096 tokens'
    ],
    redis: [
      '1:M 15 Oct 2023 08:10:01.338 * Running mode=standalone, port=6379',
      '1:M 15 Oct 2023 08:10:01.338 # Server initialized',
      '1:M 15 Oct 2023 08:10:01.338 * Ready to accept connections',
      '1:M 15 Oct 2023 08:15:22.569 * 100 changes in 300 seconds. Saving...',
      '1:M 15 Oct 2023 08:15:22.570 * Background saving started by pid 14'
    ],
    prometheus: [
      'level=info ts=2023-10-15T08:10:02.771Z caller=main.go:495 msg="Starting Prometheus"',
      'level=info ts=2023-10-15T08:10:02.775Z caller=web.go:559 component=web msg="Start listening for connections" address=0.0.0.0:9090',
      'level=info ts=2023-10-15T08:10:02.780Z caller=head.go:541 component=tsdb msg="Replaying WAL"',
      'level=info ts=2023-10-15T08:10:02.780Z caller=head.go:587 component=tsdb msg="WAL segment loaded" segment=0 maxSegment=0',
      'level=info ts=2023-10-15T08:10:02.780Z caller=head.go:593 component=tsdb msg="WAL replay completed" duration=355.088µs'
    ],
    grafana: [
      'logger=settings t=2023-10-15T08:10:03+0000 level=info msg="Starting Grafana" version=10.1.0',
      'logger=sqlstore t=2023-10-15T08:10:03+0000 level=info msg="Connecting to DB" dbtype=sqlite3',
      'logger=migrations t=2023-10-15T08:10:03+0000 level=info msg="Starting DB migrations",',
      'logger=server t=2023-10-15T08:10:03+0000 level=info msg="HTTP Server Listen" address=0.0.0.0:3001 protocol=http',
      'logger=http.server t=2023-10-15T08:10:03+0000 level=info msg="Initializing HTTP Server" address=0.0.0.0:3001 protocol=http'
    ]
  };

  if (!logData[containerId]) {
    outputElement.innerHTML += `<em class="log-error">No simulated logs available for container: ${containerId}</em>`;
    return;
  }

  const logs = logData[containerId];
  let index = 0;

  function addLog() {
    if (index < logs.length) {
      const logLine = document.createElement('div');
      logLine.className = 'terminal-line';

      const logText = logs[index];
      if (logText.includes('ERROR') || logText.includes('error')) {
        logLine.classList.add('log-error');
      } else if (logText.includes('WARN') || logText.includes('warn')) {
        logLine.classList.add('log-warn');
      } else if (logText.includes('INFO') || logText.includes('info')) {
        logLine.classList.add('log-info');
      } else if (logText.includes('DEBUG') || logText.includes('debug')) {
        logLine.classList.add('log-debug');
      }

      logLine.textContent = logText;
      outputElement.appendChild(logLine);

      outputElement.scrollTop = outputElement.scrollHeight;
      index++;

      setTimeout(addLog, 500 + Math.random() * 1000);
    }
  }

  addLog();
}

const apiPlugin = function (hook, vm) {
  hook.afterEach(function (html) {
    // Replace custom API blocks
    return html.replace(/<pre data-lang="api-(\w+)-([^"]+)">([\s\S]+?)<\/pre>/g, function (match, method, service, content) {
      const lines = content.trim().split('\n');
      const path = lines[0].trim();

      // Get base URL for the service
      const baseUrl = serviceBaseUrls[service] || `http://localhost`;

      // Check for request body
      let requestBody = null;
      if (lines.length > 1) {
        try {
          requestBody = JSON.parse(lines.slice(1).join('\n'));
        } catch (e) {
          console.error('Failed to parse request body JSON:', e);
        }
      }

      return createApiEndpoint(method.toUpperCase(), path, baseUrl, requestBody);
    });
  });
};

// Process container logs blocks
const logsPlugin = function (hook, vm) {
  hook.doneEach(function () {
    console.log("Running logs plugin after page render");

    // Find all container-logs blocks
    const logsBlocks = document.querySelectorAll('pre[data-lang="container-logs"]');
    console.log("Found container-logs blocks:", logsBlocks.length);

    logsBlocks.forEach((preElement, index) => {
      const content = preElement.textContent;
      console.log(`Processing container-logs block ${index}:`, content);

      const containers = content.trim().split('\n');
      const containerId = 'terminal-' + Math.random().toString(36).substring(2, 11);

      console.log(`Creating terminal container with ID: ${containerId}`);
      console.log(`Available containers:`, containers);

      let options = '';
      containers.forEach(container => {
        options += `<option value="${container.trim()}">${container.trim()}</option>`;
      });

      // Create container div with explicit styling to ensure visibility
      const terminalContainer = document.createElement('div');
      terminalContainer.className = 'terminal-container';
      terminalContainer.style.cssText = 'display: block; visibility: visible;';

      terminalContainer.innerHTML = `
        <div class="terminal-header">
          <span class="terminal-title">Container Logs</span>
          <select class="terminal-select" onchange="connectToContainerLogs(this.value, '${containerId}')">
            <option value="">Select a container</option>
            ${options}
          </select>
        </div>
        <div class="terminal-output" id="${containerId}" style="min-height: 200px; background-color: #1e1e1e; color: white;">
          <em>Select a container to view logs</em>
        </div>
      `;

      // Replace the pre element with our terminal container
      console.log("Replacing pre element with terminal container");
      preElement.parentNode.replaceChild(terminalContainer, preElement);

      // Debug: Check if the container was inserted into the DOM
      setTimeout(() => {
        const insertedElement = document.getElementById(containerId);
        console.log(`Terminal output element exists: ${insertedElement !== null}`);
        if (insertedElement) {
          console.log("Terminal element styles:", window.getComputedStyle(insertedElement));
        }
      }, 100);
    });
  });
};

// Process Swagger UI blocks
const swaggerPlugin = function (hook, vm) {
  hook.afterEach(function (html) {
    return html.replace(/<pre data-lang="swagger-ui">([\s\S]+?)<\/pre>/g, function (match, content) {
      const swaggerUrl = content.trim();
      const containerId = 'swagger-' + Math.random().toString(36).substring(2, 11);

      return `
          <div class="swagger-container">
            <div id="${containerId}" class="swagger-ui"></div>
            <script>
              window.onload = function() {
                SwaggerUIBundle({
                  url: "${swaggerUrl}",
                  dom_id: "#${containerId}",
                  presets: [
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIStandalonePreset
                  ],
                  layout: "BaseLayout",
                  deepLinking: true
                });
              }
            </script>
          </div>
        `;
    });
  });
};

if (window.$docsify) {
  // Make sure plugins array exists
  window.$docsify.plugins = window.$docsify.plugins || [];

  // Add our custom plugins
  window.$docsify.plugins.push(apiPlugin);
  window.$docsify.plugins.push(logsPlugin);
  window.$docsify.plugins.push(swaggerPlugin);
}

// Set default language for dynamic content loading
const getCurrentLanguage = () => {
  // Try to get from Docsify config, hash, or localStorage
  if (window.$docsify && window.$docsify.language) return window.$docsify.language;
  const hash = window.location.hash;
  if (hash.startsWith('#/')) {
    const path = hash.substring(2);
    const match = path.match(/^([a-z]{2})\//);
    if (match && match[1]) {
      return match[1];
    }
  }
  const storedLang = localStorage.getItem('language');
  if (storedLang && ['en', 'es', 'de', 'ja', 'ko'].includes(storedLang)) {
    return storedLang;
  }
  return 'en';
};