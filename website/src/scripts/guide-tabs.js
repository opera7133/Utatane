document.documentElement.classList.add('tabs-enabled');
const tabs = [...document.querySelectorAll('[role="tab"]')];
const selectTab = (tab, updateHash = false) => {
  for (const item of tabs) {
    const selected = item === tab;
    item.setAttribute('aria-selected', String(selected));
    item.tabIndex = selected ? 0 : -1;
    document.getElementById(item.getAttribute('aria-controls')).hidden = !selected;
  }
  if (updateHash) history.replaceState(null, '', '#' + tab.id.replace('tab-', ''));
};
for (const tab of tabs) {
  tab.addEventListener('click', () => selectTab(tab, true));
  tab.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
    event.preventDefault();
    const next = tabs[(tabs.indexOf(tab) + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length];
    selectTab(next, true);
    next.focus();
  });
}
selectTab(location.hash === '#veteran' ? tabs[1] : tabs[0]);
