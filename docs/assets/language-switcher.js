// Language switcher functionality
document.addEventListener('DOMContentLoaded', function() {
  // Create language select element
  const select = document.createElement('select');
  select.className = 'language-select';
  select.innerHTML = Object.entries(window.$docsify.selectLanguage.locales)
    .map(([code, name]) => `
      <option value="${code}" ${code === window.$docsify.language ? 'selected' : ''}>
        ${name}
      </option>
    `)
    .join('');
  
  // Add to page
  document.body.appendChild(select);
  
  // Handle language change
  select.addEventListener('change', function(e) {
    const lang = e.target.value;
    localStorage.setItem('language', lang);
    window.location.href = `?lang=${lang}`;
  });
});