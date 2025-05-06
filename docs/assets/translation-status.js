// Translation status indicator
(function() {
  const translationStatus = {
    'en': {
      name: 'English',
      status: 'complete',
      lastUpdated: '2024-03-20'
    },
    'es': {
      name: 'Español',
      status: 'complete',
      lastUpdated: '2024-03-20'
    },
    'de': {
      name: 'Deutsch',
      status: 'complete',
      lastUpdated: '2024-03-20'
    },
    'ja': {
      name: '日本語',
      status: 'complete',
      lastUpdated: '2024-03-20'
    },
    'ko': {
      name: '한국어',
      status: 'complete',
      lastUpdated: '2024-03-20'
    }
  };

  // Add translation status to the page
  function addTranslationStatus() {
    const currentLang = window.$docsify.language;
    const status = translationStatus[currentLang];
    
    if (!status) return;

    const statusDiv = document.createElement('div');
    statusDiv.className = 'translation-status';
    statusDiv.innerHTML = `
      <div class="translation-status-content">
        <span class="status-label">Translation Status:</span>
        <span class="status-value ${status.status}">${status.status}</span>
        <span class="last-updated">Last updated: ${status.lastUpdated}</span>
      </div>
    `;

    // Add styles
    const style = document.createElement('style');
    style.textContent = `
      .translation-status {
        position: fixed;
        bottom: 20px;
        right: 20px;
        background: rgba(0, 0, 0, 0.8);
        color: white;
        padding: 10px 15px;
        border-radius: 5px;
        font-size: 14px;
        z-index: 1000;
      }
      .translation-status-content {
        display: flex;
        align-items: center;
        gap: 10px;
      }
      .status-label {
        font-weight: bold;
      }
      .status-value {
        padding: 2px 8px;
        border-radius: 3px;
        text-transform: capitalize;
      }
      .status-value.complete {
        background: #42b983;
      }
      .status-value.partial {
        background: #f0ad4e;
      }
      .status-value.incomplete {
        background: #d9534f;
      }
      .last-updated {
        font-size: 12px;
        opacity: 0.8;
      }
    `;

    document.head.appendChild(style);
    document.body.appendChild(statusDiv);
  }

  // Initialize when Docsify is ready
  window.$docsify = window.$docsify || {};
  window.$docsify.plugins = (window.$docsify.plugins || []).concat(function(hook) {
    hook.afterEach(function(html) {
      addTranslationStatus();
      return html;
    });
  });
})(); 