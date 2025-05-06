// Handle coverpage loading based on selected language
(function() {
  // Add a plugin to Docsify to properly handle the coverpage based on language
  const coverpagePlugin = function(hook, vm) {
    hook.beforeEach(function(content) {
      // Only handle root path and coverpage
      if (vm.route.path === '/' || vm.route.path === '/README' || vm.route.path === '/_coverpage') {
        const currentLang = window.$docsify.language || 'en';
        console.log('Loading coverpage for language:', currentLang);
        
        // Try to load the language-specific coverpage
        return new Promise(resolve => {
          fetch(`${currentLang}/_coverpage.md`)
            .then(response => {
              if (response.ok) {
                return response.text();
              }
              throw new Error('Language-specific coverpage not found');
            })
            .then(translatedContent => {
              console.log(`Successfully loaded coverpage from ${currentLang}/_coverpage.md`);
              resolve(translatedContent);
            })
            .catch(error => {
              console.error('Error loading language-specific coverpage:', error);
              console.log('Falling back to default English coverpage');
              
              // Try the default English coverpage as fallback
              fetch('en/_coverpage.md')
                .then(response => response.text())
                .then(englishContent => {
                  resolve(englishContent);
                })
                .catch(() => {
                  // If all else fails, just use the content as is
                  resolve(content);
                });
            });
        });
      }
      
      return content;
    });
  };
  
  // Register the plugin with Docsify
  window.$docsify.plugins = [].concat(coverpagePlugin, window.$docsify.plugins || []);
})();