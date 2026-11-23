import { sb, escapeHtml, getSettings, setText, toast, errorMessage } from './app.js';

const SUITES = [
  {
    key: 'clinical',
    title: 'الحقيبة الإكلينيكية',
    desc: 'أدوات تقييم الحالة النفسية والسلوكية داخل السياق الإكلينيكي.',
    icon: 'fa-solid fa-stethoscope',
    tone: 'bg-emerald-50 text-emerald-700'
  },
  {
    key: 'special',
    title: 'حقيبة الفئات الخاصة',
    desc: 'أدوات مخصصة لفئات وسياقات تقييم مختلفة.',
    icon: 'fa-solid fa-users-rectangle',
    tone: 'bg-amber-50 text-amber-700'
  }
];

function card(item) {
  return `
    <a href="patient.html?assessment=${encodeURIComponent(item.slug)}"
       class="card-hover bg-white rounded-2xl border border-slate-200 p-6 flex flex-col min-h-[210px]">
      <div class="flex items-start justify-between gap-3 mb-4">
        <span class="w-11 h-11 rounded-xl bg-emerald-50 text-emerald-700 flex items-center justify-center text-lg">
          <i class="fa-solid fa-clipboard-check"></i>
        </span>
        <span class="text-[10px] font-bold text-slate-400 font-en uppercase">v${escapeHtml(item.version)}</span>
      </div>
      <h4 class="text-lg font-extrabold text-slate-900 mb-2">${escapeHtml(item.titleAr)}</h4>
      <p class="font-en text-xs font-bold text-emerald-700 mb-2">${escapeHtml(item.titleEn)}</p>
      <p class="text-xs text-slate-500 leading-relaxed mb-5 flex-1">${escapeHtml(item.descriptionAr || '')}</p>
      <div class="flex items-center justify-between pt-4 border-t border-slate-100">
        <span class="text-xs font-bold text-slate-500"><i class="fa-solid fa-list-ol ml-1"></i>${escapeHtml(item.itemCount)} بند</span>
        <span class="text-xs font-extrabold text-emerald-700 flex items-center gap-1">ابدأ <i class="fa-solid fa-arrow-left"></i></span>
      </div>
    </a>`;
}

function renderCatalog(data) {
  const grid = document.getElementById('catalog');
  grid.innerHTML = SUITES.map(suite => {
    const items = data.filter(item => (item.suite || 'clinical') === suite.key);
    return `
      <section class="suite-section">
        <div class="flex flex-wrap items-center gap-3 mb-5">
          <span class="w-10 h-10 rounded-xl ${suite.tone} flex items-center justify-center text-lg">
            <i class="${suite.icon}"></i>
          </span>
          <div>
            <h4 class="text-lg font-extrabold text-slate-900">${suite.title}</h4>
            <p class="text-xs text-slate-500 mt-0.5">${suite.desc}</p>
          </div>
          <span class="mr-auto text-[11px] font-bold text-slate-400">${items.length} اختبار</span>
        </div>
        <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          ${items.length
            ? items.map(card).join('')
            : '<p class="col-span-full rounded-2xl border border-dashed border-slate-200 bg-white py-10 text-center text-sm text-slate-400">لا توجد اختبارات في هذه الحقيبة حالياً.</p>'}
        </div>
      </section>`;
  }).join('');
}

async function init() {
  try {
    const settings = await getSettings();
    setText('site-name', settings['public.siteNameAr'] || 'منصة التقييم الإكلينيكي');
    setText('university-name', settings['public.universityAr'] || 'جامعة المنوفية');
    setText('hero-text', settings['public.welcomeAr'] || '');
    setText('footer-text', settings['public.footerAr'] || '');
  } catch (e) {
    console.warn('Settings load failed', e);
  }

  const { data, error } = await sb.rpc('get_public_catalog');
  const loading = document.getElementById('catalog-loading');
  const grid = document.getElementById('catalog');

  if (error) {
    loading.innerHTML = `<div class="col-span-full bg-rose-50 border border-rose-200 rounded-2xl p-6 text-center text-sm text-rose-700 font-bold">${escapeHtml(errorMessage(error))}</div>`;
    loading.classList.remove('hidden');
    return;
  }

  loading.classList.add('hidden');
  grid.classList.remove('hidden');

  if (!data || data.length === 0) {
    grid.innerHTML = `<div class="bg-white border border-slate-200 rounded-2xl p-10 text-center text-slate-500 text-sm">لا توجد اختبارات متاحة حالياً.</div>`;
    return;
  }

  renderCatalog(data);
}

init().catch(e => toast(errorMessage(e), 'error'));
