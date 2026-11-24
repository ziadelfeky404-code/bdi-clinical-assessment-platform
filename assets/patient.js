import { sb, escapeHtml, getSettings, setText, toast, errorMessage } from './app.js';

const params = new URLSearchParams(location.search);
const requestedSlug = params.get('assessment') || '';

const state = {
  assessment: null,
  index: 0,
  answers: {},
  timer: null,
  submitting: false,
  settings: {}
};

const steps = ['step-intro', 'step-select', 'step-runner', 'step-done'];

function showStep(id) {
  steps.forEach(s => document.getElementById(s).classList.toggle('hidden', s !== id));
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function cancelAdvance() {
  if (state.timer) clearTimeout(state.timer);
  state.timer = null;
}

function scheduleAdvance() {
  cancelAdvance();
  state.timer = setTimeout(() => {
    state.timer = null;
    nextItem();
  }, 220);
}

function totalItems() {
  return state.assessment?.items?.length || 0;
}

function renderCurrent() {
  const items = state.assessment.items;
  const item = items[state.index];
  const answered = Object.keys(state.answers).length;
  const pct = Math.round((answered / items.length) * 100);

  document.getElementById('item-counter').textContent = `البند ${state.index + 1} من ${items.length}`;
  document.getElementById('q-number').textContent = `البند رقم (${item.position})`;
  document.getElementById('progress-percent').textContent = `${pct}%`;
  document.getElementById('progress-bar').style.width = `${pct}%`;
  document.getElementById('prev-btn').disabled = state.index === 0;

  const selected = state.answers[item.position]?.[0];
  const container = document.getElementById('options-container');
  const prompt = (item.textAr || item.textEn) ? `
    <div class="mb-4 rounded-xl bg-white border border-slate-200 p-4">
      <p class="text-sm sm:text-base font-bold text-slate-800 leading-relaxed">${escapeHtml(item.textAr || '')}</p>
      ${item.textEn ? `<p class="font-en text-[11px] text-slate-400 mt-1.5">${escapeHtml(item.textEn)}</p>` : ''}
    </div>` : '';
  const figure = item.imageUrl ? `
    <div class="mb-4 flex justify-center rounded-xl bg-white border border-slate-200 p-3">
      <img src="${escapeHtml(item.imageUrl)}" alt="محتوى البند" class="max-h-[58vh] w-auto max-w-full object-contain" />
    </div>` : '';
  container.innerHTML = `${prompt}${figure}` + item.options.map((opt, optIndex) => {
    const isNumericLabel = /^\d+$/.test(String(opt.ar || '').trim());
    const badge = isNumericLabel ? '' : `<span class="opt-number">${optIndex + 1}</span>`;
    return `
    <button type="button" class="opt-card w-full text-right rounded-xl border px-4 py-3.5 flex items-start gap-3 ${
      opt.score === selected ? 'selected border-emerald-700' : 'border-slate-200 bg-white'
    }" data-score="${escapeHtml(opt.score)}">
      ${badge}
      <span class="flex-1 flex flex-col gap-1">
        <span class="text-sm sm:text-base font-semibold text-slate-800 leading-relaxed">${escapeHtml(opt.ar)}</span>
        <span class="font-en text-[11px] text-slate-400">${escapeHtml(opt.en)}</span>
      </span>
    </button>`;
  }).join('');

  container.querySelectorAll('[data-score]').forEach(btn => {
    btn.addEventListener('click', () => {
      if (state.submitting) return;
      state.answers[item.position] = [Number(btn.dataset.score)];
      document.getElementById('submit-error').classList.add('hidden');
      renderCurrent();
      scheduleAdvance();
    });
  });
}

function nextItem() {
  if (state.index < totalItems() - 1) {
    state.index += 1;
    renderCurrent();
  } else {
    submitSession();
  }
}

function prevItem() {
  cancelAdvance();
  if (state.index > 0) {
    state.index -= 1;
    renderCurrent();
  }
}

function startRunner(assessment) {
  state.assessment = assessment;
  state.index = 0;
  state.answers = {};
  state.submitting = false;
  document.getElementById('runner-instructions').textContent = assessment.instructionsAr || 'اقرأ العبارات واختر الأقرب إلى شعورك.';
  document.getElementById('submit-error').classList.add('hidden');
  showStep('step-runner');
  renderCurrent();
}

async function submitSession() {
  if (state.submitting) return;
  const answers = Object.entries(state.answers)
    .map(([position, scores]) => ({ position: Number(position), scores }))
    .sort((a, b) => a.position - b.position);

  if (answers.length !== totalItems()) {
    showSubmitError('يرجى الإجابة على جميع البنود قبل الإنهاء.');
    return;
  }

  state.submitting = true;
  document.getElementById('submit-error').classList.add('hidden');
  const startBtn = document.getElementById('start-btn');
  const originalText = startBtn.innerHTML;
  startBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> جارٍ التسجيل…';
  startBtn.disabled = true;

  try {
    const { data, error } = await sb.rpc('submit_assessment', {
      p_slug: state.assessment.slug,
      p_patient_name: document.getElementById('patient-name').value,
      p_age: Number(document.getElementById('patient-age').value) || null,
      p_gender: document.getElementById('patient-gender').value,
      p_examiner: document.getElementById('examiner-name').value,
      p_notes: '',
      p_answers: answers
    });
    if (error) throw error;
    if (!data?.ok) throw new Error('تعذر تسجيل الاستجابات');

    setText('session-code', data.code);
    showStep('step-done');
  } catch (e) {
    showSubmitError(errorMessage(e));
    state.index = totalItems() - 1;
    renderCurrent();
  } finally {
    state.submitting = false;
    startBtn.innerHTML = originalText;
    startBtn.disabled = false;
  }
}

function showSubmitError(message) {
  setText('submit-error-text', message);
  document.getElementById('submit-error').classList.remove('hidden');
}

async function chooseAssessment(slug) {
  try {
    const { data, error } = await sb.rpc('get_assessment_public', { p_slug: slug });
    if (error) throw error;
    if (!data) throw new Error('هذه الأداة غير متاحة حالياً');
    startRunner(data);
  } catch (e) {
    toast(errorMessage(e), 'error');
  }
}

async function init() {
  document.getElementById('prev-btn').addEventListener('click', prevItem);
  window.__retrySubmit = submitSession;

  try {
    state.settings = await getSettings();
    setText('site-name', state.settings['public.siteNameAr'] || 'منصة التقييم الإكلينيكي');
    setText('university-name', state.settings['public.universityAr'] || 'جامعة المنوفية');
    setText('consent-text', state.settings['public.consentAr'] || 'أوافق على استخدام استجاباتي لأغراض التقييم الإكلينيكي.');
    setText('footer-text', state.settings['public.footerAr'] || '');
    setText('thanks-text', state.settings['public.thanksAr'] || 'شكراً لوقتك وتعاونك.');
  } catch (e) {
    console.warn('Settings load failed', e);
  }

  const { data: catalog, error: catalogError } = await sb.rpc('get_public_catalog');
  if (catalogError) {
    toast(errorMessage(catalogError), 'error');
    return;
  }

  if (requestedSlug) {
    const match = (catalog || []).find(a => a.slug === requestedSlug);
    if (match) {
      document.getElementById('selected-assessment-banner').classList.remove('hidden');
      setText('selected-assessment-name', match.titleAr);
    }
  }

  document.getElementById('start-btn').addEventListener('click', async () => {
    if (!document.getElementById('consent').checked) {
      toast('يرجى الموافقة قبل البدء', 'error');
      return;
    }
    if (requestedSlug) {
      await chooseAssessment(requestedSlug);
      return;
    }

    const list = document.getElementById('select-list');
    if (!catalog || catalog.length === 0) {
      list.innerHTML = '<p class="text-sm text-slate-500">لا توجد أدوات متاحة حالياً.</p>';
    } else {
      list.innerHTML = catalog.map(a => `
        <button type="button" data-slug="${escapeHtml(a.slug)}" class="card-hover text-right rounded-2xl border border-slate-200 bg-white p-5">
          <h3 class="text-base font-extrabold text-slate-900 mb-1">${escapeHtml(a.titleAr)}</h3>
          <p class="font-en text-[11px] font-bold text-emerald-700 mb-2">${escapeHtml(a.titleEn)}</p>
          <p class="text-xs text-slate-500 mb-4">${escapeHtml(a.descriptionAr || '')}</p>
          <span class="text-xs font-extrabold text-emerald-700">ابدأ <i class="fa-solid fa-arrow-left"></i></span>
        </button>
      `).join('');
      list.querySelectorAll('[data-slug]').forEach(btn => {
        btn.addEventListener('click', () => chooseAssessment(btn.dataset.slug));
      });
    }
    showStep('step-select');
  });
}

init().catch(e => toast(errorMessage(e), 'error'));
