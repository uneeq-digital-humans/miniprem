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
      
      // Always add language prefix
      const pathWithoutLang = currentPath.replace(/^(en|es|de|ja|ko)\//, '');
      newPath = lang + '/' + pathWithoutLang;
      
      // Update URL without the query parameter
      window.location.hash = '#/' + newPath;
      
      // Force reload to ensure everything is consistent
      setTimeout(() => {
        window.location.reload();
      }, 100);
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
    // Apply stored language immediately on page load
    const language = getCurrentLanguage();
    
    // If we have a URL param but it doesn't match the stored language,
    // update the stored language
    const urlParams = new URLSearchParams(window.location.search);
    const urlLang = urlParams.get('lang');
    if (urlLang && urlLang !== language && ['en', 'es', 'de', 'ja', 'ko'].includes(urlLang)) {
      localStorage.setItem('language', urlLang);
      window.$docsify.language = urlLang;
    }
    
    // Ensure URL structure matches selected language
    redirectToCorrectLanguage();
    
    // Wait for Docsify to initialize
    setTimeout(() => {
      const sidebar = document.querySelector('.sidebar');
      if (sidebar) {
        const langSelector = createLanguageSelector();
        sidebar.insertBefore(langSelector, sidebar.firstChild);
      }
    }, 500);
  });
  
  // Extract language from URL or localStorage
  function getCurrentLanguage() {
    // First check URL parameter
    const urlParams = new URLSearchParams(window.location.search);
    const urlLang = urlParams.get('lang');
    if (urlLang && ['en', 'es', 'de', 'ja', 'ko'].includes(urlLang)) {
      return urlLang;
    }
    
    // Then check URL hash for language path
    const hash = window.location.hash;
    if (hash.startsWith('#/')) {
      const path = hash.substring(2); // Remove #/
      const match = path.match(/^([a-z]{2})\//);
      if (match && match[1]) {
        const lang = match[1];
        if (['en', 'es', 'de', 'ja', 'ko'].includes(lang)) {
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
  
  // Function to redirect to the correct language version
  function redirectToCorrectLanguage() {
    const language = getCurrentLanguage();
    const currentHash = window.location.hash;
    
    // Remove the query parameter from URL
    const url = new URL(window.location.href);
    if (url.searchParams.has('lang')) {
      console.log(`Removing lang parameter from URL`);
      url.searchParams.delete('lang');
      window.history.replaceState({}, document.title, url.toString());
    }
    
    // Special handling for root URL/coverpage
    if (!currentHash || currentHash === '#/' || currentHash === '#/README') {
      // Allow root path to show the coverpage - don't redirect
      console.log("Root path detected, showing coverpage");
      // Set the language but don't redirect
      window.$docsify.language = language;
      return;
    }

    // Special case for _coverpage - convert to root to show coverpage
    if (currentHash === '#/_coverpage') {
      window.location.hash = '#/';
      window.location.reload();
      return;
    }
    
    // For other pages without language prefix, add the current language prefix
    if (currentHash.startsWith('#/') && !currentHash.match(/^#\/(en|es|de|ja|ko)\//)) {
      const path = currentHash.substring(2); // Remove #/
      window.location.hash = '#/' + language + '/' + path;
      window.location.reload();
      return;
    }
    
    // If using a different language than in the URL, update the URL
    if (currentHash.startsWith('#/')) {
      const urlLangMatch = currentHash.match(/^#\/([a-z]{2})\//);
      if (urlLangMatch && urlLangMatch[1] !== language) {
        const path = currentHash.substring(2); // Remove #/
        const pathWithoutLang = path.replace(/^[a-z]{2}\//, '');
        const newPath = language + '/' + pathWithoutLang;
        
        console.log(`Redirecting to language (${language}): #/${newPath}`);
        window.location.hash = '#/' + newPath;
        window.location.reload();
      }
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
      
      // Special handling for root path/coverpage
      if (vm.route.path === '/' || vm.route.path === '/README') {
        // Try to load the coverpage for the current language
        return new Promise(resolve => {
          fetch(currentLang + '/_coverpage.md')
            .then(response => {
              if (response.ok) {
                return response.text();
              }
              throw new Error('Language-specific coverpage not found');
            })
            .then(translatedContent => {
              console.log('Using coverpage from: ' + currentLang + '/_coverpage.md');
              resolve(translatedContent);
            })
            .catch(() => {
              // Fall back to default coverpage
              console.log('Fallback to default coverpage');
              resolve(content);
            });
        });
      }
      
      // If already in correct language path, return content as is
      if (vm.route.path.startsWith('/' + currentLang + '/')) {
        return content;
      }
      
      // For other languages, try to load the localized version
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
    });
  });
})();