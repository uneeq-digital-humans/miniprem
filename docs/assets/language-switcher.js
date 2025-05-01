// Language switcher functionality
(function() {
  // Create language selector component
  function createLanguageSelector() {
    const currentLang = window.$docsify.language || 'en';
    const locales = window.$docsify.selectLanguage.locales;
    
    const langSelector = document.createElement('div');
    langSelector.className = 'language-selector';
    
    const selectBox = document.createElement('select');
    selectBox.addEventListener('change', function() {
      const lang = this.value;
      localStorage.setItem('language', lang);
      
      // Properly redirect to the translated version with correct path
      const currentPath = window.location.hash.split('?')[0].replace('#/', '');
      let newPath = '';
      
      // If switching to English, remove language prefix
      if (lang === 'en') {
        // Remove any language prefix from the path
        newPath = currentPath.replace(/^[a-z]{2}\//, '');
      } else {
        // For other languages, add the language prefix
        // First remove any existing language prefix
        const pathWithoutLang = currentPath.replace(/^[a-z]{2}\//, '');
        newPath = lang + '/' + pathWithoutLang;
      }
      
      // Navigate to the new path
      window.location.hash = '#/' + newPath;
    });
    
    // Add options for all languages
    Object.keys(locales).forEach(code => {
      const option = document.createElement('option');
      option.value = code;
      option.textContent = locales[code];
      option.selected = code === currentLang;
      selectBox.appendChild(option);
    });
    
    langSelector.appendChild(selectBox);
    return langSelector;
  }
  
  // Add hook to insert language selector after navigation is ready
  document.addEventListener('DOMContentLoaded', function() {
    // Wait for Docsify to initialize
    setTimeout(() => {
      const sidebar = document.querySelector('.sidebar');
      if (sidebar) {
        const langSelector = createLanguageSelector();
        sidebar.insertBefore(langSelector, sidebar.firstChild);
      }
    }, 500);
    
    // Apply stored language on initial load
    redirectToCorrectLanguage();
  });
  
  // Extract language from URL or localStorage
  function getCurrentLanguage() {
    // First try from URL hash
    const hash = window.location.hash;
    if (hash.startsWith('#/')) {
      const path = hash.substring(2); // Remove #/
      const match = path.match(/^([a-z]{2})\//);
      if (match && match[1]) {
        const lang = match[1];
        if (['en', 'es', 'de', 'ja', 'ko'].includes(lang)) {
          localStorage.setItem('language', lang);
          return lang;
        }
      }
    }
    
    // Then try from localStorage
    const storedLang = localStorage.getItem('language');
    if (storedLang && ['en', 'es', 'de', 'ja', 'ko'].includes(storedLang)) {
      return storedLang;
    }
    
    // Default to English
    return 'en';
  }
  
  // Function to redirect to the correct language version on initial load
  function redirectToCorrectLanguage() {
    const storedLang = localStorage.getItem('language');
    if (!storedLang || storedLang === 'en') {
      return; // No redirection needed for English
    }
    
    const currentHash = window.location.hash;
    
    // Only redirect if we're not already on a localized path
    if (currentHash.startsWith('#/') && !currentHash.match(/#\/[a-z]{2}\//)) {
      const path = currentHash.substring(2); // Remove #/
      const newPath = storedLang + '/' + path;
      
      // Use timeout to ensure this happens after Docsify initialization
      setTimeout(() => {
        console.log(`Redirecting to stored language (${storedLang}): #/${newPath}`);
        window.location.hash = '#/' + newPath;
      }, 100);
    }
  }
  
  // Set the current language for Docsify
  window.$docsify.language = getCurrentLanguage();
  
  // Handle content loading based on language
  window.$docsify.plugins = [].concat(window.$docsify.plugins, function(hook, vm) {
    // Run this once at startup to handle initial page load
    hook.init(function() {
      console.log('Docsify init with language:', window.$docsify.language);
    });
    
    hook.beforeEach(function(content) {
      const currentLang = window.$docsify.language;
      
      // If already in correct language path, return content as is
      if (vm.route.path.startsWith('/' + currentLang + '/')) {
        return content;
      }
      
      // If not English, try to load the localized version
      if (currentLang !== 'en') {
        const currentPath = vm.route.path;
        const localizedPath = '/' + currentLang + currentPath;
        
        return new Promise(resolve => {
          // Try to fetch localized version first
          fetch(localizedPath + '.md')
            .then(response => {
              if (response.ok) {
                return response.text();
              }
              throw new Error('Localized version not found');
            })
            .then(translatedContent => {
              console.log('Found translation at ' + localizedPath);
              resolve(translatedContent);
            })
            .catch(() => {
              // Fall back to English version
              console.log('No translation found for ' + localizedPath + ', using English');
              resolve(content);
            });
        });
      }
      
      return content;
    });
  });
})();