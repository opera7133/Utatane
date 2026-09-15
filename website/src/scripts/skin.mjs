export function installSkinSelector() {
  const key = 'utatane-doc-skin';
  const valid = new Set(['paper', 'glass', 'classic']);
  const selectors = document.querySelectorAll('[data-doc-skin-select]');
  let value = 'paper';
  try { value = localStorage.getItem(key) || value; } catch { /* file: and private browsing may deny storage. */ }
  if (!valid.has(value)) value = 'paper';
  document.documentElement.dataset.docSkin = value;
  for (const selector of selectors) {
    selector.value = value;
    selector.addEventListener('change', () => {
      const next = valid.has(selector.value) ? selector.value : 'paper';
      document.documentElement.dataset.docSkin = next;
      try { localStorage.setItem(key, next); } catch { /* The selection still works for this page. */ }
    });
  }
}
