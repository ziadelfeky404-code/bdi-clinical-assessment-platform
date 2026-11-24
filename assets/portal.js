import { getSettings, setText } from './app.js';

async function init() {
  try {
    const settings = await getSettings();
    setText('site-name', settings['public.siteNameAr'] || 'منصة التقييم الإكلينيكي');
    setText('university-name', settings['public.universityAr'] || 'جامعة المنوفية');
    setText('hero-text', settings['public.welcomeAr'] || 'أداة تقييم إكلينيكي متكاملة تُستخدم داخل السياق العلاجي والتربوي.');
    setText('footer-text', settings['public.footerAr'] || 'جامعة المنوفية — منصة التقييم الإكلينيكي');
  } catch (error) {
    console.warn('Settings load failed', error);
  }
}

init();
