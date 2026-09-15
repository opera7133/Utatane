import ja from './data/ja.json' with { type: 'json' };
import en from './data/en.json' with { type: 'json' };
import zhHans from './data/zh-Hans.json' with { type: 'json' };
import zhHant from './data/zh-Hant.json' with { type: 'json' };
import ko from './data/ko.json' with { type: 'json' };
import { sitePath } from './site.mjs';

export const locales = { ja, en, 'zh-Hans': zhHans, 'zh-Hant': zhHant, ko };
export const localeCodes = Object.keys(locales);
export const localePath = (code, route = '') => {
  const relative = [locales[code].meta.directory, route].filter(Boolean).join('/');
  return sitePath(relative && !relative.endsWith('/') ? `${relative}/` : relative);
};
export const translations = code => key => {
  const text = locales[code].home[key];
  if (typeof text !== 'string') throw new Error(`Missing translation: ${code}/${key}`);
  return text;
};
export const languageLabels = { ja: '日本語', en: 'EN', 'zh-Hans': '简体', 'zh-Hant': '繁體', ko: '한국어' };
