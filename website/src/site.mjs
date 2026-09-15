export const origin = (process.env.UTATANE_SITE_ORIGIN || 'https://dl.wmsci.com').replace(/\/$/, '');
export const base = (process.env.UTATANE_SITE_BASE ?? '/utatane').replace(/^\/?(.*?)\/?$/, '$1');
export const sitePath = (path = '') => {
  const joined = [base, path.replace(/^\//, '')].filter(Boolean).join('/');
  return joined ? `/${joined}${path === '' ? '/' : ''}` : '/';
};
export const siteURL = (path = '') => origin + sitePath(path);
export const repositoryURL = 'https://github.com/opera7133/Utatane';
