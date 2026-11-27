import { sb, escapeHtml, getSettings, setText, toast, errorMessage } from './app.js';

const params = new URLSearchParams(location.search);
const initialCode = (params.get('code') || '').replace(/\D/g, '').slice(0, 8);

const state = {
  assessment: null,
  accessCode: initialCode,
  index: 0,
  answers: {},
  timer: null,
  submitting: false,
  isSpecialist: false,
  loading: false,
  settings: {},
  ravenLayout: null
};

const steps = ['step-intro', 'step-runner', 'step-done'];

const reducedMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function showStep(id, focusId) {
  steps.forEach(s => {
    const el = document.getElementById(s);
    if (!el) return;
    const visible = s === id;
    el.classList.toggle('hidden', !visible);
    el.setAttribute('aria-hidden', visible ? 'false' : 'true');
  });
  window.scrollTo({ top: 0, behavior: reducedMotion() ? 'auto' : 'smooth' });
  if (focusId) {
    requestAnimationFrame(() => document.getElementById(focusId)?.focus({ preventScroll: true }));
  }
}

function announce(message) {
  setText('item-announce', message);
}

function setFieldError(id, message) {
  setText(id, message);
  const field = id === 'access-code-error' ? document.getElementById('access-code-input') : document.getElementById('consent');
  if (field) {
    if (message) field.setAttribute('aria-invalid', 'true');
    else field.removeAttribute('aria-invalid');
  }
}

function cancelAdvance() {
  if (state.timer) clearTimeout(state.timer);
  state.timer = null;
}

function scheduleAdvance() {
  cancelAdvance();
  if (state.index >= totalItems() - 1) return; // never auto-submit the final answer
  const delay = reducedMotion() ? 900 : 500;
  state.timer = setTimeout(() => {
    state.timer = null;
    nextItem(true);
  }, delay);
}

function totalItems() {
  return state.assessment?.items?.length || 0;
}

function getRavenLayout(item) {
  const match = (item.imageUrl || '').match(/raven\/([A-E]\d{2})/);
  return match && state.ravenLayout ? state.ravenLayout[match[1]] : null;
}

// Crops the original scan with CSS only: no figure is redrawn or recoloured.
function cropStyle(imageUrl, rect) {
  const [x, y, w, h] = rect;
  const px = (100 * x / (1 - w)).toFixed(3);
  const py = (100 * y / (1 - h)).toFixed(3);
  return `background-image:url('${escapeHtml(imageUrl)}');background-size:${(100 / w).toFixed(3)}% ${(100 / h).toFixed(3)}%;background-position:${px}% ${py}%;background-repeat:no-repeat;background-color:#fff;`;
}

function renderRaven(item, selected, focusOption) {
  const layout = getRavenLayout(item);
  const selectedIndex = selected == null ? -1 : Number(selected) - 1;
  const dropRect = layout.missing;
  const dropStyle = [
    `left:${(dropRect[0] * 100).toFixed(3)}%`,
    `top:${(dropRect[1] * 100).toFixed(3)}%`,
    `width:${(dropRect[2] * 100).toFixed(3)}%`,
    `height:${(dropRect[3] * 100).toFixed(3)}%`,
    selectedIndex >= 0 && layout.options[selectedIndex] ? cropStyle(item.imageUrl, layout.options[selectedIndex]) : ''
  ].filter(Boolean).join(';');

  document.getElementById('item-prompt').innerHTML = '';
  document.getElementById('item-figure').innerHTML = `
    <div class="mb-4 flex justify-center rounded-xl bg-white border border-slate-300 p-2 sm:p-3">
      <div class="raven-matrix">
        <img src="${escapeHtml(item.imageUrl)}" alt="مصفوفة بصرية" draggable="false" class="max-h-[58vh] w-auto max-w-full object-contain" />
        <div id="raven-drop" class="raven-drop" role="button" tabindex="0"
          aria-label="المكان الناقص، اسحب الخيار إليه أو اختر خياراً من القائمة"
          data-filled="${selectedIndex >= 0 ? 'true' : 'false'}" style="${dropStyle}">
          ${selectedIndex >= 0 ? '' : '<span class="px-1 text-center text-[10px] font-extrabold text-amber-900">المكان الناقص</span>'}
        </div>
      </div>
    </div>`;

  const container = document.getElementById('options-container');
  container.className = 'raven-options';
  container.setAttribute('aria-label', 'خيارات إكمال المصفوفة');
  container.innerHTML = layout.options.map((rect, index) => `
    <button type="button" role="radio" aria-checked="${index === selectedIndex}"
      tabindex="${index === selectedIndex || (selectedIndex < 0 && index === 0) ? '0' : '-1'}"
      draggable="true" data-score="${index + 1}" data-opt-index="${index}"
      class="raven-option" aria-label="الخيار ${index + 1}">
      <span class="opt-number" aria-hidden="true">${index + 1}</span>
      <span class="raven-option-image" style="${cropStyle(item.imageUrl, rect)}" aria-hidden="true"></span>
    </button>`).join('');

  const buttons = [...container.querySelectorAll('[data-score]')];
  buttons.forEach((btn, index) => {
    btn.addEventListener('click', () => selectOption(index));
    btn.addEventListener('dragstart', e => {
      e.dataTransfer.setData('text/plain', String(index));
      e.dataTransfer.effectAllowed = 'copy';
      btn.dataset.dragging = 'true';
    });
    btn.addEventListener('dragend', () => { btn.dataset.dragging = 'false'; });
    btn.addEventListener('keydown', e => {
      const keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'];
      if (!keys.includes(e.key)) return;
      e.preventDefault();
      const dir = (e.key === 'ArrowRight' || e.key === 'ArrowDown') ? 1 : -1;
      const next = (index + dir + buttons.length) % buttons.length;
      buttons[next].focus();
      selectOption(next, false);
    });
  });

  const drop = document.getElementById('raven-drop');
  drop.addEventListener('dragover', e => { e.preventDefault(); drop.dataset.over = 'true'; });
  drop.addEventListener('dragleave', () => { delete drop.dataset.over; });
  drop.addEventListener('drop', e => {
    e.preventDefault();
    delete drop.dataset.over;
    const index = Number(e.dataTransfer.getData('text/plain'));
    if (Number.isInteger(index)) selectOption(index);
  });
  drop.addEventListener('click', () => (buttons[selectedIndex] || buttons[0])?.focus());
  drop.addEventListener('keydown', e => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      (buttons[selectedIndex] || buttons[0])?.focus();
    }
  });

  setText('auto-advance-hint', 'اسحب الخيار إلى المكان الناقص، أو اضغط على الخيار وانتقل تلقائياً للبند التالي. يمكنك الرجوع لتعديل إجابتك.');
  if (focusOption) (buttons[selectedIndex] || buttons[0])?.focus({ preventScroll: true });
}

function renderCurrent(focusOption = false) {
  if (!state.assessment) return;
  const items = state.assessment.items;
  const item = items[state.index];
  const answered = Object.keys(state.answers).length;
  const pct = Math.round((answered / items.length) * 100);

  setText('item-counter', `البند ${state.index + 1} من ${items.length}`);
  setText('q-number', `البند رقم (${item.position})`);
  setText('progress-percent', `${pct}%`);
  document.getElementById('progress-bar').style.width = `${pct}%`;
  document.getElementById('progress-track').setAttribute('aria-valuenow', String(pct));
  document.getElementById('prev-btn').disabled = state.index === 0;
  document.getElementById('runner-submit-btn').setAttribute(
    'aria-label', `تأكيد الإجابات وإنهاء الجلسة، أُجيب على ${answered} من ${items.length}`
  );

  const selected = state.answers[item.position]?.[0];
  const raven = getRavenLayout(item);
  let buttons = [];

  if (raven) {
    renderRaven(item, selected, focusOption);
  } else {
    setText('auto-advance-hint', 'عند الاختيار ستنتقل تلقائياً إلى البند التالي. يمكنك الرجوع لتعديل إجابتك، أو استخدام زر الإنهاء في أي وقت.');
    const container = document.getElementById('options-container');
    container.className = 'space-y-3';
    container.setAttribute('aria-label', 'خيارات الإجابة');
    document.getElementById('item-prompt').innerHTML = (item.textAr || item.textEn) ? `
      <div class="mb-4 rounded-xl bg-white border border-slate-300 p-4">
        <p class="text-sm sm:text-base font-bold text-slate-800 leading-relaxed">${escapeHtml(item.textAr || '')}</p>
        ${item.textEn ? `<p class="font-en text-xs text-slate-600 mt-1.5">${escapeHtml(item.textEn)}</p>` : ''}
      </div>` : '';

    document.getElementById('item-figure').innerHTML = item.imageUrl ? `
      <div class="mb-4 flex justify-center rounded-xl bg-white border border-slate-300 p-3">
        <img src="${escapeHtml(item.imageUrl)}" alt="محتوى البند" class="max-h-[55vh] w-auto max-w-full object-contain" />
      </div>` : '';

    container.innerHTML = item.options.map((opt, optIndex) => {
      const isNumericLabel = /^\d+$/.test(String(opt.ar || '').trim());
      const badge = isNumericLabel ? '' : `<span class="opt-number" aria-hidden="true">${optIndex + 1}</span>`;
      const isSelected = opt.score === selected;
      return `
      <button type="button" role="radio" aria-checked="${isSelected}" tabindex="${isSelected || (!selected && optIndex === 0) ? '0' : '-1'}"
        class="opt-card w-full text-right rounded-xl border px-4 py-3.5 flex items-start gap-3 min-h-[52px] ${
          isSelected ? 'selected border-emerald-700' : 'border-slate-300 bg-white'
        }" data-score="${escapeHtml(opt.score)}" data-opt-index="${optIndex}">
        ${badge}
        <span class="flex-1 flex flex-col gap-1">
          <span class="text-sm sm:text-base font-semibold text-slate-800 leading-relaxed">${escapeHtml(opt.ar)}</span>
          ${opt.en ? `<span class="font-en text-xs text-slate-600">${escapeHtml(opt.en)}</span>` : ''}
        </span>
      </button>`;
    }).join('');

    buttons = [...container.querySelectorAll('[data-score]')];
    buttons.forEach((btn, idx) => {
      btn.addEventListener('click', () => selectOption(idx));
      btn.addEventListener('keydown', e => {
        const keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'];
        if (!keys.includes(e.key)) return;
        e.preventDefault();
        const dir = (e.key === 'ArrowRight' || e.key === 'ArrowDown') ? 1 : -1;
        const next = (idx + dir + buttons.length) % buttons.length;
        buttons[next].focus();
        selectOption(next, false);
      });
    });

    if (focusOption) (buttons.find(b => b.getAttribute('aria-checked') === 'true') || buttons[0])?.focus({ preventScroll: true });
  }

  announce(`البند ${state.index + 1} من ${items.length}. ${item.textAr || ''}`);
}

function selectOption(index, moveFocus = true) {
  if (state.submitting) return;
  const item = state.assessment.items[state.index];
  const opt = item.options[index];
  if (!opt) return;
  cancelAdvance();
  state.answers[item.position] = [Number(opt.score)];
  document.getElementById('submit-error').classList.add('hidden');
  renderCurrent(moveFocus);
  scheduleAdvance();
}

function nextItem(focus = false) {
  if (state.index < totalItems() - 1) {
    state.index += 1;
    renderCurrent(focus);
  }
}

function prevItem() {
  cancelAdvance();
  if (state.index > 0) {
    state.index -= 1;
    renderCurrent(true);
  }
}

function startRunner(assessment) {
  state.assessment = assessment;
  state.index = 0;
  state.answers = {};
  state.submitting = false;
  setText('runner-instructions', assessment.instructionsAr || 'اقرأ العبارات واختر الأقرب إلى شعورك.');
  document.getElementById('submit-error').classList.add('hidden');
  showStep('step-runner', 'options-container');
  renderCurrent(true);
}

async function submitSession() {
  if (state.submitting || !state.assessment) return;
  cancelAdvance();
  const answers = Object.entries(state.answers)
    .map(([position, scores]) => ({ position: Number(position), scores }))
    .sort((a, b) => a.position - b.position);

  if (answers.length !== totalItems()) {
    const missing = totalItems() - answers.length;
    showSubmitError(`يرجى الإجابة على جميع البنود قبل الإنهاء. متبقٍ ${missing} بنداً.`);
    return;
  }

  state.submitting = true;
  document.getElementById('submit-error').classList.add('hidden');
  const submitBtn = document.getElementById('runner-submit-btn');
  submitBtn.setAttribute('aria-busy', 'true');
  submitBtn.disabled = true;
  const original = submitBtn.innerHTML;
  submitBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i> جارٍ التسجيل…';

  try {
    const { data, error } = await sb.rpc('submit_assessment', {
      p_slug: state.assessment.slug,
      p_patient_name: document.getElementById('patient-name').value,
      p_age: Number(document.getElementById('patient-age').value) || null,
      p_gender: document.getElementById('patient-gender').value,
      p_examiner: document.getElementById('examiner-name').value,
      p_notes: '',
      p_answers: answers,
      p_access_code: state.accessCode
    });
    if (error) throw error;
    if (!data?.ok) throw new Error('تعذر تسجيل الاستجابات');

    setText('session-code', data.code);
    showStep('step-done', 'thanks-title');
  } catch (e) {
    showSubmitError(errorMessage(e));
  } finally {
    state.submitting = false;
    submitBtn.removeAttribute('aria-busy');
    submitBtn.disabled = false;
    submitBtn.innerHTML = original;
  }
}

async function detectSpecialist() {
  try {
    const { data: auth } = await sb.auth.getUser();
    if (!auth.user) return;
    const { data, error } = await sb.rpc('is_specialist');
    if (error || data !== true) return;
    state.isSpecialist = true;
    document.getElementById('autofill-btn').classList.remove('hidden');
  } catch {
    // Keep the demo control hidden for patients.
  }
}

async function fillRemaining() {
  if (!state.isSpecialist || state.submitting || !state.assessment) return;
  const confirmed = window.confirm('سيتم تعبئة كل البنود المتبقية بإجابات تجريبية وإنشاء تقرير كامل. هل تريد المتابعة؟');
  if (!confirmed) return;

  cancelAdvance();
  state.assessment.items.forEach((item, index) => {
    if (state.answers[item.position]) return;
    const options = item.options || [];
    if (!options.length) return;
    const option = options[(item.position + index) % options.length];
    state.answers[item.position] = [Number(option.score)];
  });
  renderCurrent(false);
  await submitSession();
}

function showSubmitError(message) {
  setText('submit-error-text', message);
  document.getElementById('submit-error').classList.remove('hidden');
  const btn = document.getElementById('retry-submit-btn');
  btn?.focus({ preventScroll: true });
}

async function startWithCode(code) {
  if (state.loading) return;
  const cleaned = String(code || '').replace(/\D/g, '').slice(0, 8);
  setFieldError('access-code-error', '');
  document.getElementById('selected-assessment-banner').classList.add('hidden');

  if (!/^\d{8}$/.test(cleaned)) {
    setFieldError('access-code-error', 'أدخل رقم الدخول المكوّن من 8 أرقام.');
    document.getElementById('access-code-input').focus();
    return;
  }
  if (!document.getElementById('consent').checked) {
    setFieldError('consent-error', 'يرجى الموافقة قبل البدء.');
    document.getElementById('consent').focus();
    return;
  }

  state.loading = true;
  const btn = document.getElementById('start-btn');
  btn.setAttribute('aria-busy', 'true');
  btn.disabled = true;
  const original = btn.innerHTML;
  btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i> جارٍ التحقق…';
  try {
    const { data, error } = await sb.rpc('get_assessment_by_access_code', { p_code: cleaned });
    if (error) throw error;
    if (!data) throw new Error('رقم الدخول غير صالح أو منتهي الصلاحية');
    state.accessCode = cleaned;
    setText('selected-assessment-name', data.titleAr || '');
    document.getElementById('selected-assessment-banner').classList.remove('hidden');
    startRunner(data);
  } catch (e) {
    setFieldError('access-code-error', errorMessage(e));
    document.getElementById('access-code-input').focus();
  } finally {
    state.loading = false;
    btn.removeAttribute('aria-busy');
    btn.disabled = false;
    btn.innerHTML = original;
  }
}

async function init() {
  document.getElementById('prev-btn').addEventListener('click', prevItem);
  document.getElementById('autofill-btn').addEventListener('click', fillRemaining);
  document.getElementById('runner-submit-btn').addEventListener('click', submitSession);
  document.getElementById('retry-submit-btn').addEventListener('click', submitSession);
  document.getElementById('intro-form').addEventListener('submit', e => {
    e.preventDefault();
    startWithCode(document.getElementById('access-code-input').value);
  });
  document.getElementById('consent').addEventListener('change', () => setFieldError('consent-error', ''));
  document.getElementById('access-code-input').addEventListener('input', e => {
    e.target.value = e.target.value.replace(/\D/g, '').slice(0, 8);
    setFieldError('access-code-error', '');
  });
  document.getElementById('finish-btn').addEventListener('click', () => window.close());
  document.getElementById('copy-session-btn').addEventListener('click', async () => {
    const code = document.getElementById('session-code').textContent;
    try {
      await navigator.clipboard.writeText(code);
      toast('تم نسخ رقم الجلسة');
    } catch {
      toast('تعذر النسخ، يمكنك تحديد الرقم يدوياً', 'error');
    }
  });

  if (initialCode) {
    document.getElementById('access-code-input').value = initialCode;
  }

  try {
    const response = await fetch('assets/raven/raven_layout.json');
    if (response.ok) state.ravenLayout = await response.json();
  } catch (e) {
    console.warn('Raven layout load failed', e);
  }

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

  await detectSpecialist();
  document.getElementById('access-code-input').focus({ preventScroll: true });
}

init().catch(e => toast(errorMessage(e), 'error'));
