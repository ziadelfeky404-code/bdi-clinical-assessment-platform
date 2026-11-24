import { sb, escapeHtml, getSettings, setText, toast, errorMessage, formatDate, setupDialog } from './app.js';

const state = {
  profile: null,
  isAdmin: false,
  isDemo: false,
  assessments: [],
  reports: [],
  settings: {},
  editing: null,
  editorItems: [],
  currentReportId: null,
  lastFocused: null
};

const SETTING_FIELDS = [
  ['public.siteNameAr', 'اسم الموقع (عربي)'],
  ['public.siteNameEn', 'Site name (English)'],
  ['public.universityAr', 'اسم الجامعة (عربي)'],
  ['public.universityEn', 'University (English)'],
  ['public.welcomeAr', 'نص الترحيب (عربي)'],
  ['public.footerAr', 'تذييل الصفحة (عربي)'],
  ['public.consentAr', 'نص الموافقة (عربي)'],
  ['public.consentEn', 'Consent text (English)'],
  ['public.thanksAr', 'رسالة الإنهاء (عربي)'],
  ['public.thanksEn', 'Completion message (English)']
];

const TONE_BY_KEY = {
  minimal: 'tone-emerald', mild: 'tone-amber', moderate: 'tone-orange', severe: 'tone-rose',
  low: 'tone-emerald', high: 'tone-rose',
  balanced: 'tone-emerald', developing: 'tone-amber', strained: 'tone-rose',
  within: 'tone-emerald', elevated: 'tone-amber', marked: 'tone-rose',
  average: 'tone-emerald', above: 'tone-sky', superior: 'tone-amber'
};

const SUITE_LABELS = {
  clinical: 'الحقيبة الإكلينيكية',
  special: 'حقيبة الفئات الخاصة'
};

function showLogin() {
  document.getElementById('login-view').classList.remove('hidden');
  document.getElementById('app-view').classList.add('hidden');
  document.getElementById('header-actions').classList.add('hidden');
  document.getElementById('demo-banner').classList.add('hidden');
}

function showApp() {
  document.getElementById('login-view').classList.add('hidden');
  document.getElementById('app-view').classList.remove('hidden');
  document.getElementById('header-actions').classList.remove('hidden');
  document.getElementById('header-actions').classList.add('flex');
}

function switchTab(name) {
  ['dashboard', 'reports', 'assessments', 'settings', 'team'].forEach(tab => {
    const panel = document.getElementById(`tab-${tab}`);
    panel.classList.toggle('hidden', tab !== name);
    panel.setAttribute('aria-hidden', tab === name ? 'false' : 'true');
  });
  document.querySelectorAll('nav button[data-tab]').forEach(btn => {
    const active = btn.dataset.tab === name;
    btn.classList.toggle('active', active);
    btn.setAttribute('role', 'tab');
    btn.setAttribute('aria-selected', active ? 'true' : 'false');
  });
  document.querySelectorAll('section[id^="tab-"]').forEach(panel => panel.setAttribute('role', 'tabpanel'));
  window.scrollTo({ top: 0, behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
}

function prettyJson(value) {
  try { return JSON.stringify(value, null, 2); } catch { return '[]'; }
}

async function loadAssessments() {
  const { data, error } = await sb.from('assessments').select('*').order('sort_order');
  if (error) throw error;
  state.assessments = data || [];
  renderAssessments();

  const select = document.getElementById('report-filter');
  const current = select.value;
  select.innerHTML = '<option value="all">كل الاختبارات</option>' + state.assessments.map(a =>
    `<option value="${escapeHtml(a.id)}">${escapeHtml(a.title_ar)}</option>`
  ).join('');
  select.value = current || 'all';
  renderCodePanel();
}

function renderCodePanel() {
  const select = document.getElementById('access-code-assessment');
  if (!select) return;
  const current = select.value;
  select.innerHTML = state.assessments.filter(a => a.active).map(a =>
    `<option value="${escapeHtml(a.id)}">${escapeHtml(a.title_ar)}</option>`
  ).join('');
  if (current && [...select.options].some(o => o.value === current)) select.value = current;
}

async function loadAccessCodes() {
  const host = document.getElementById('access-code-list');
  if (!host) return;
  try {
    const { data, error } = await sb.rpc('list_access_codes');
    if (error) throw error;
    const rows = data || [];
    if (!rows.length) {
      host.innerHTML = '<p class="text-xs text-slate-600">لم يتم إصدار رموز بعد.</p>';
      return;
    }
    host.innerHTML = `
      <table class="min-w-full text-xs">
        <thead class="text-slate-700"><tr>
          <th class="text-right py-2">الاختبار</th><th class="text-right py-2">الرقم</th>
          <th class="text-right py-2">الانتهاء</th><th class="text-right py-2">الحالة</th>
          <th class="text-right py-2">إجراء</th>
        </tr></thead>
        <tbody>${rows.map(r => `<tr class="border-t border-slate-100">
          <td class="py-2 font-bold">${escapeHtml(r.assessmentTitleAr)}</td>
          <td class="py-2 font-en" dir="ltr">${escapeHtml(r.maskedCode)}</td>
          <td class="py-2">${escapeHtml(formatDate(r.expiresAt, true))}</td>
          <td class="py-2">${r.usedAt ? 'مستخدم' : r.revoked ? 'ملغي' : 'صالح'}</td>
          <td class="py-2">${!r.usedAt && !r.revoked ? `<button type="button" class="font-bold text-rose-700 rounded focus-ring" data-revoke-code="${escapeHtml(r.id)}">إلغاء</button>` : '—'}</td>
        </tr>`).join('')}</tbody>
      </table>`;
    host.querySelectorAll('[data-revoke-code]').forEach(btn => btn.addEventListener('click', async () => {
      try {
        const { error } = await sb.rpc('revoke_access_code', { p_id: btn.dataset.revokeCode });
        if (error) throw error;
        toast('تم إلغاء الرقم');
        await loadAccessCodes();
      } catch (e) { toast(errorMessage(e), 'error'); }
    }));
  } catch (e) {
    host.innerHTML = `<p class="text-xs text-rose-700">${escapeHtml(errorMessage(e))}</p>`;
  }
}

function openAccessCodeModal(code, expiresAt, assessmentTitle) {
  const modal = document.getElementById('access-code-modal');
  state.lastFocused = document.activeElement;
  setText('access-code-value', code);
  setText('access-code-expires', `للاختبار: ${assessmentTitle} — ينتهي في ${formatDate(expiresAt, true)}`);
  modal.classList.remove('hidden');
  document.getElementById('access-code-close-btn').focus();
}

function closeAccessCodeModal() {
  // The plaintext code is shown once only; never leave it in the hidden DOM.
  setText('access-code-value', '');
  document.getElementById('access-code-modal').classList.add('hidden');
  if (state.lastFocused?.focus) state.lastFocused.focus({ preventScroll: true });
  loadAccessCodes();
}

async function issueAccessCode(assessmentId) {
  const status = document.getElementById('access-code-status');
  status.textContent = '';
  if (!assessmentId) { status.textContent = 'اختر الاختبار أولاً.'; return; }
  const btn = document.getElementById('issue-code-btn');
  btn.setAttribute('aria-busy', 'true');
  btn.disabled = true;
  try {
    const { data, error } = await sb.rpc('issue_assessment_access_code', { p_assessment_id: assessmentId });
    if (error) throw error;
    if (!data?.ok) throw new Error('تعذر إصدار رقم الدخول');
    openAccessCodeModal(data.code, data.expiresAt, data.assessmentTitleAr);
    toast('تم إنشاء رقم الدخول');
  } catch (e) {
    status.textContent = errorMessage(e);
  } finally {
    btn.removeAttribute('aria-busy');
    btn.disabled = false;
  }
}

async function loadReports() {
  const { data, error } = await sb.from('reports')
    .select('*').order('created_at', { ascending: false }).limit(300);
  if (error) throw error;
  state.reports = data || [];
  renderReports();
  renderDashboard();
}

async function loadSettings() {
  try {
    state.settings = await getSettings();
  } catch (e) {
    state.settings = {};
  }
  renderSettings();
}

async function loadTeam() {
  if (!state.isAdmin) return;
  const { data, error } = await sb.from('specialists').select('*').order('created_at');
  if (error) { toast(errorMessage(error), 'error'); return; }

  const selfId = state.profile?.id;
  const tbody = (data || []).map(s => {
    const isSelf = s.id === selfId;
    const isDemo = s.email === 'demo@menoufia.edu.eg';
    const locked = isSelf || isDemo;
    return `
    <tr class="border-b border-slate-100 text-sm">
      <td class="py-3 px-3 font-bold text-slate-800">${escapeHtml(s.full_name || '—')}${isSelf ? '<span class="mr-2 text-[10px] text-emerald-700">(أنت)</span>' : ''}</td>
      <td class="py-3 px-3 text-slate-600" dir="ltr" style="text-align:right">${escapeHtml(s.email)}</td>
      <td class="py-3 px-3">${s.role === 'admin' ? 'مدير نظام' : 'متخصص'}</td>
      <td class="py-3 px-3">${s.active ? '<span class="text-emerald-700 font-bold">مفعّل</span>' : '<span class="text-rose-700 font-bold">معطل</span>'}</td>
      <td class="py-3 px-3">
        <div class="flex items-center gap-2">
          <button data-team-active="${escapeHtml(s.id)}" data-active="${s.active}" ${locked ? 'disabled title="لا يمكن تغيير حالة هذا الحساب"' : ''}
            class="text-[11px] font-bold rounded-lg border px-2 py-1 disabled:opacity-40 ${s.active ? 'border-rose-200 text-rose-700 hover:bg-rose-50' : 'border-emerald-200 text-emerald-700 hover:bg-emerald-50'}">
            ${s.active ? 'تعطيل' : 'تفعيل'}
          </button>
          <select data-team-role="${escapeHtml(s.id)}" ${locked ? 'disabled title="لا يمكن تغيير صلاحية هذا الحساب"' : ''}
            class="text-[11px] font-bold rounded-lg border border-slate-200 px-2 py-1 bg-white disabled:opacity-40">
            <option value="specialist" ${s.role === 'specialist' ? 'selected' : ''}>متخصص</option>
            <option value="admin" ${s.role === 'admin' ? 'selected' : ''}>مدير نظام</option>
          </select>
          <button data-team-delete="${escapeHtml(s.id)}" data-name="${escapeHtml(s.full_name || s.email)}"
            ${locked ? 'disabled title="لا يمكن حذف هذا الحساب"' : ''}
            class="text-[11px] font-bold rounded-lg border border-rose-200 text-rose-700 px-2 py-1 hover:bg-rose-50 disabled:opacity-40">
            حذف
          </button>
        </div>
      </td>
    </tr>`;
  }).join('');

  const host = document.getElementById('team-list');
  host.innerHTML = `
    <table class="w-full min-w-[760px] text-right">
      <thead class="text-[11px] text-slate-500 border-b border-slate-200">
        <tr><th class="py-2 px-3">الاسم</th><th class="py-2 px-3">البريد</th><th class="py-2 px-3">الصلاحية</th><th class="py-2 px-3">الحالة</th><th class="py-2 px-3">تحكم</th></tr>
      </thead>
      <tbody>${tbody || '<tr><td colspan="5" class="py-6 text-center text-slate-400">لا يوجد متخصصون</td></tr>'}</tbody>
    </table>`;

  host.querySelectorAll('[data-team-active]').forEach(btn => {
    btn.addEventListener('click', async () => {
      try {
        const { error } = await sb.from('specialists').update({ active: btn.dataset.active !== 'true' }).eq('id', btn.dataset.teamActive);
        if (error) throw error;
        toast('تم تحديث حالة الحساب');
        loadTeam();
      } catch (e) {
        toast(errorMessage(e), 'error');
      }
    });
  });

  host.querySelectorAll('[data-team-role]').forEach(select => {
    select.addEventListener('change', async () => {
      try {
        const { error } = await sb.from('specialists').update({ role: select.value }).eq('id', select.dataset.teamRole);
        if (error) throw error;
        toast('تم تحديث الصلاحية');
        loadTeam();
      } catch (e) {
        toast(errorMessage(e), 'error');
      }
    });
  });

  host.querySelectorAll('[data-team-delete]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const name = btn.dataset.name || 'هذا الحساب';
      if (!window.confirm(`هل تريد حذف حساب «${name}» نهائياً؟ لا يمكن التراجع.`)) return;
      try {
        const { error } = await sb.rpc('delete_specialist_account', { p_user_id: btn.dataset.teamDelete });
        if (error) throw error;
        toast('تم حذف الحساب');
        loadTeam();
      } catch (e) {
        toast(errorMessage(e), 'error');
      }
    });
  });
}

function severityLabel(report) {
  return `<span class="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-bold ${TONE_BY_KEY[report.severity_key] || 'tone-slate'}">
    <span class="severity-dot" style="background:currentColor"></span>${escapeHtml(report.severity_ar)}
  </span>`;
}

function renderDashboard() {
  const critical = state.reports.filter(r => (r.alerts || []).some(a => a.severity === 'critical' || a.severity === 'high'));
  setText('stat-sessions', state.reports.length);
  setText('stat-reports', state.reports.length);
  setText('stat-alerts', critical.length);
  setText('stat-tests', state.assessments.filter(a => a.active).length);

  const recent = state.reports.slice(0, 6);
  document.getElementById('recent-reports').innerHTML = recent.length ? `
    <table class="w-full min-w-[620px] text-right text-sm">
      <thead class="text-[11px] text-slate-500 border-b border-slate-200">
        <tr><th class="py-2 px-2">رقم الجلسة</th><th class="py-2 px-2">المفحوص</th><th class="py-2 px-2">الدرجة</th><th class="py-2 px-2">التصنيف</th><th class="py-2 px-2">التاريخ</th></tr>
      </thead>
      <tbody>
        ${recent.map(r => `
          <tr class="border-b border-slate-100 cursor-pointer hover:bg-slate-50" data-report="${escapeHtml(r.id)}">
            <td class="py-2.5 px-2 font-en font-bold text-emerald-800" dir="ltr">${escapeHtml(r.snapshot?.patientCode || '—')}</td>
            <td class="py-2.5 px-2 font-bold text-slate-800">${escapeHtml(r.snapshot?.patientName || '—')}</td>
            <td class="py-2.5 px-2 font-extrabold">${r.raw_score}/${r.max_score}</td>
            <td class="py-2.5 px-2">${severityLabel(r)}</td>
            <td class="py-2.5 px-2 text-xs text-slate-500">${formatDate(r.created_at, true)}</td>
          </tr>`).join('')}
      </tbody>
    </table>` : '<p class="py-10 text-center text-sm text-slate-400">لا توجد تقارير بعد.</p>';

  document.querySelectorAll('[data-report]').forEach(row => {
    row.addEventListener('click', () => openReport(row.dataset.report));
  });

  const alerts = critical.slice(0, 8);
  document.getElementById('dashboard-alerts').innerHTML = alerts.length ? alerts.map(r => {
    const top = (r.alerts || []).find(a => a.severity === 'critical') || r.alerts[0];
    return `<button data-report="${escapeHtml(r.id)}" class="w-full text-right rounded-xl border ${top.severity === 'critical' ? 'border-rose-200 bg-rose-50' : 'border-amber-200 bg-amber-50'} p-4 hover:opacity-80 transition">
      <p class="text-xs font-extrabold ${top.severity === 'critical' ? 'text-rose-800' : 'text-amber-800'}">${escapeHtml(top.titleAr)}</p>
      <p class="text-[11px] text-slate-600 mt-1">${escapeHtml(r.snapshot?.patientName || '—')} • ${formatDate(r.created_at, true)}</p>
    </button>`;
  }).join('') : '<p class="text-sm text-slate-400">لا توجد تنبيهات حالياً.</p>';

  document.querySelectorAll('#dashboard-alerts [data-report]').forEach(btn => {
    btn.addEventListener('click', () => openReport(btn.dataset.report));
  });
}

function renderReports() {
  const search = (document.getElementById('report-search').value || '').trim().toLowerCase();
  const filter = document.getElementById('report-filter').value;
  const rows = state.reports.filter(r => {
    const matchFilter = filter === 'all' || r.assessment_id === filter;
    const name = (r.snapshot?.patientName || '').toLowerCase();
    const code = (r.snapshot?.patientCode || '').toLowerCase();
    return matchFilter && (!search || name.includes(search) || code.includes(search));
  });

  document.getElementById('reports-table').innerHTML = rows.length ? `
    <table class="w-full min-w-[760px] text-right text-sm">
      <thead class="text-[11px] text-slate-500 border-b border-slate-200">
        <tr>
          <th class="py-2 px-2">المفحوص</th><th class="py-2 px-2">الاختبار</th>
          <th class="py-2 px-2">الدرجة</th><th class="py-2 px-2">التصنيف</th>
          <th class="py-2 px-2">تنبيهات</th><th class="py-2 px-2">التاريخ</th><th class="py-2 px-2"></th>
        </tr>
      </thead>
      <tbody>
        ${rows.map(r => `
          <tr class="border-b border-slate-100 hover:bg-slate-50">
            <td class="py-3 px-2 font-bold text-slate-800">${escapeHtml(r.snapshot?.patientName || '—')}</td>
            <td class="py-3 px-2 text-xs text-slate-600">${escapeHtml(r.snapshot?.assessmentTitleAr || '—')}</td>
            <td class="py-3 px-2 font-extrabold">${r.raw_score}/${r.max_score}</td>
            <td class="py-3 px-2">${severityLabel(r)}</td>
            <td class="py-3 px-2">${(r.alerts || []).length ? `<span class="text-rose-700 font-bold"><i class="fa-solid fa-triangle-exclamation ml-1"></i>${r.alerts.length}</span>` : '<span class="text-slate-300">—</span>'}</td>
            <td class="py-3 px-2 text-xs text-slate-500">${formatDate(r.created_at, true)}</td>
            <td class="py-3 px-2"><button data-open-report="${escapeHtml(r.id)}" class="text-xs font-bold text-emerald-700">عرض</button></td>
          </tr>`).join('')}
      </tbody>
    </table>` : '<p class="py-10 text-center text-sm text-slate-400">لا توجد تقارير مطابقة.</p>';

  document.querySelectorAll('[data-open-report]').forEach(btn => {
    btn.addEventListener('click', () => openReport(btn.dataset.openReport));
  });
}

function shortLabel(text, max = 64) {
  const value = String(text || '').trim();
  return value.length > max ? `${value.slice(0, max)}…` : value;
}

function buildClinicalNarrative(report) {
  const items = report.snapshot?.items || [];
  const alerts = report.alerts || [];
  const critical = alerts.filter(a => a.severity === 'critical');
  const key = report.severity_key;

  const meaning = {
    minimal: 'لا توجد مؤشرات ذات دلالة سريرية على اضطراب في الحالة النفسية ضمن استجابات هذه الأداة.',
    mild: 'مؤشرات خفيفة على ضغط في الحالة النفسية، تُقرأ ضمن السياق الإكلينيكي العام.',
    moderate: 'مؤشرات متوسطة تستدعي تقييماً إكلينيكياً موسعاً ومناقشتها مع المفحوص.',
    severe: 'مؤشرات شديدة تتطلب تدخلاً إكلينيكياً متخصصاً ومتابعة قريبة.',
    low: 'مستوى الضغط ضمن المعدل المعتاد.',
    high: 'مستوى ضغط مرتفع يستدعي تدخلاً إكلينيكياً.',
    balanced: 'نمط تكيف متوازن ومرن مع الضغوط.',
    developing: 'بعض مهارات التكيف تحتاج إلى تنمية وتدعيم.',
    strained: 'نمط تكيف مرهق يستدعي دعماً إكلينيكياً.',
    below: 'النتيجة أقل من المتوسط المرجعي لهذه الأداة.',
    average: 'النتيجة ضمن المتوسط المرجعي لهذه الأداة.',
    above: 'النتيجة أعلى من المتوسط المرجعي لهذه الأداة.',
    superior: 'النتيجة في نطاق مرتفع مقارنة بالمتوسط المرجعي.',
    within: 'لم تتجاوز المقاييس السريرية الرئيسية العتبة المعتمدة في الجدول التقريبي.',
    elevated: 'ارتفاع سريري واضح في واحد أو أكثر من المقاييس الرئيسية.',
    marked: 'ارتفاع سريري شديد في واحد أو أكثر من المقاييس الرئيسية.'
  };

  let diagnosis = `التصنيف المبدئي وفق الأداة: ${report.severity_ar} (الدرجة ${report.raw_score} من ${report.max_score}).`;
  if (meaning[key]) diagnosis += ` ${meaning[key]}`;
  if (critical.length) {
    diagnosis += ' توجد مؤشرات حرجة مرتبطة ببعض البنود؛ يلزم تقييم مباشر لمخاطر الإيذاء النفس قبل أي استنتاج نهائي.';
  } else if (alerts.length) {
    diagnosis += ' توجد مؤشرات إضافية تحتاج متابعة إكلينيكية مختصرة.';
  }

  const scaleScores = report.snapshot?.scaleScores || {};
  const validityKeys = new Set(['L', 'F', 'K', 'Q']);
  const interpretiveMeta = (report.snapshot?.scaleMeta || []).filter(s =>
    s && s.key && !s.hidden && !validityKeys.has(s.key) && Number.isFinite(Number(scaleScores[s.key])));
  // Scales carrying raw mean/sd are converted to T scores by the server.
  // Compare their stored scores with the T metric (50/10), not the raw norm.
  const metricOf = s => Number.isFinite(Number(s.mean)) && Number.isFinite(Number(s.sd))
    ? { mean: 50, sd: 10 }
    : { mean: Number(s.mean), sd: Number(s.sd) };
  const highScales = interpretiveMeta.filter(s => {
    const value = Number(scaleScores[s.key]);
    const cutoff = Number(s.elevate);
    if (Number.isFinite(cutoff)) return value >= cutoff;
    const { mean, sd } = metricOf(s);
    return Number.isFinite(mean) && Number.isFinite(sd) && value >= mean + 1.5 * sd;
  });
  const lowScales = interpretiveMeta.filter(s => {
    const value = Number(scaleScores[s.key]);
    const { mean, sd } = metricOf(s);
    return Number.isFinite(mean) && Number.isFinite(sd) && value <= mean - sd;
  });
  if (highScales.length) {
    diagnosis += ` ارتفاع لافت على: ${highScales.map(s => s.ar || s.key).join('، ')}.`;
  }

  const alertPositions = new Set(alerts.map(a => Number(a.position)).filter(n => Number.isFinite(n)));
  const highItems = items.filter(i => Number(i.score) >= 2).sort((a, b) => Number(b.score) - Number(a.score));
  const lowItems = items.filter(i => Number(i.score) <= 1 && !alertPositions.has(Number(i.position)));
  const labelOf = i => shortLabel(i.textAr || i.textEn || 'بند بدون نص');

  const strengths = lowScales.length
    ? lowScales.slice(0, 5).map(s => `${s.ar || s.key}: ${Number(scaleScores[s.key]).toFixed(1)} — ضمن النطاق الأقل في الجدول المرجعي.`)
    : lowItems.length
      ? lowItems.slice(0, 3).map(i => `استجابة منخفضة على البند (${i.position}): ${labelOf(i)}`)
      : ['لم تبرز بنود منخفضة بوضوح؛ وتُقرأ النتيجة في ضوء التصنيف العام.'];

  const weaknesses = highScales.length
    ? highScales.slice(0, 5).map(s => `${s.ar || s.key}: ${Number(scaleScores[s.key]).toFixed(1)} — فوق العتبة المرجعية، ويُفسّر مع بقية المقاييس.`)
    : highItems.length
      ? highItems.slice(0, 3).map(i => `استجابة مرتفعة على البند (${i.position}): ${labelOf(i)}`)
      : ['لا توجد بنود مرتفعة بشكل لافت ضمن هذه الاستجابات.'];

  const recommendations = [];
  if (critical.length) {
    recommendations.push('تقييم مباشر وعاجل لمخاطر الإيذاء النفس، وتفعيل خطة سلامة تحت إشراف المتخصص، مع إحالة لطبيب نفسي عند اللزوم.');
  }
  if (key === 'severe' || key === 'high' || key === 'strained' || key === 'marked') {
    recommendations.push('إحالة إلى أخصائي نفسي أو طبيب نفسي لوضع خطة علاج متكاملة ومتابعة قريبة الأجل.');
  } else if (key === 'moderate' || key === 'developing' || key === 'elevated') {
    recommendations.push('جلسات متابعة منتظمة مع إعادة تقييم بالأداة نفسها بعد 4 أسابيع تقريباً.');
  } else if (key === 'mild') {
    recommendations.push('متابعة دورية وتعزيز استراتيجيات التأقلم والدعم الاجتماعي.');
  } else {
    recommendations.push('مناقشة النتيجة مع المفحوص في جلسة إكلينيكية، وإعادة التقييم عند تغير الحالة.');
  }
  if (alerts.length && !critical.length) {
    recommendations.push('مراجعة البنود التي أثارت التنبيهات في الجلسة القادمة وتوثيق التغير.');
  }
  recommendations.push('تُعد هذه الصياغة مساعدة قرار آلية مبنية على الاستجابات، ولا تُغني عن الحكم الإكلينيكي المتخصص.');

  return { diagnosis, strengths, weaknesses, recommendations };
}

function openReport(id) {
  const r = state.reports.find(x => x.id === id);
  if (!r) return;
  state.currentReportId = id;
  const snap = r.snapshot || {};
  const alerts = r.alerts || [];
  const items = snap.items || [];
  const narrative = r.narrative || buildClinicalNarrative(r);
  document.getElementById('report-edit-panel').classList.add('hidden');
  document.getElementById('report-modal-body').classList.remove('hidden');

  document.getElementById('report-modal-body').innerHTML = `
    <div class="border-b border-slate-200 pb-5 mb-5">
      <h2 class="text-2xl font-extrabold text-slate-900">${escapeHtml(snap.assessmentTitleAr || 'تقرير التقييم')}</h2>
      <p class="font-en text-sm font-bold text-emerald-700 mt-1">${escapeHtml(snap.assessmentTitleEn || '')}</p>
      <p class="text-xs text-slate-500 mt-2">نسخة الأداة: ${escapeHtml(r.version)} • ${formatDate(r.created_at, true)}</p>
    </div>

    <div class="grid sm:grid-cols-2 gap-4 mb-6">
      <div class="rounded-xl bg-slate-50 border border-slate-200 p-4 text-sm space-y-1.5">
        <p><span class="text-slate-500">المفحوص:</span> <strong>${escapeHtml(snap.patientName || '—')}</strong></p>
        <p><span class="text-slate-500">العمر:</span> <strong>${snap.patientAge ? escapeHtml(snap.patientAge) + ' سنة' : '—'}</strong></p>
        <p><span class="text-slate-500">النوع:</span> <strong>${escapeHtml(snap.patientGender || '—')}</strong></p>
        <p><span class="text-slate-500">الفاحص:</span> <strong>${escapeHtml(snap.examinerName || '—')}</strong></p>
      </div>
      <div class="rounded-xl border-2 p-5 ${TONE_BY_KEY[r.severity_key] || 'tone-slate'}">
        <p class="text-xs font-bold opacity-80">الدرجة الخام</p>
        <p class="text-4xl font-extrabold my-1">${r.raw_score}<span class="text-lg opacity-60"> / ${r.max_score}</span></p>
        <p class="text-base font-extrabold mt-2">${escapeHtml(r.severity_ar)}</p>
        <p class="font-en text-xs font-bold opacity-80">${escapeHtml(r.severity_en)}</p>
        <p class="text-xs leading-relaxed mt-3">${escapeHtml(r.severity_desc_ar || '')}</p>
      </div>
    </div>

    <div class="avoid-break mb-6 rounded-xl border-2 p-5 ${TONE_BY_KEY[r.severity_key] || 'tone-slate'}">
      <h3 class="font-extrabold mb-2 flex items-center gap-2 text-sm"><i class="fa-solid fa-stethoscope"></i> التشخيص المبدئي</h3>
      <p class="text-xs leading-relaxed font-semibold">${escapeHtml(narrative.diagnosis)}</p>
    </div>

    ${alerts.length ? `
      <div class="mb-6">
        <h3 class="font-extrabold text-rose-800 mb-3 flex items-center gap-2"><i class="fa-solid fa-triangle-exclamation"></i> التنبيهات الإكلينيكية</h3>
        <div class="space-y-3">
          ${alerts.map(a => `
            <div class="rounded-xl border ${a.severity === 'critical' ? 'border-rose-300 bg-rose-50' : 'border-amber-300 bg-amber-50'} p-4">
              <p class="text-sm font-extrabold ${a.severity === 'critical' ? 'text-rose-900' : 'text-amber-900'}">${escapeHtml(a.titleAr)}</p>
              <p class="text-xs leading-relaxed mt-1 text-slate-700">${escapeHtml(a.bodyAr)}</p>
              <p class="font-en text-[11px] font-bold text-slate-500 mt-2">${escapeHtml(a.titleEn)}</p>
            </div>`).join('')}
        </div>
      </div>` : ''}

    ${Object.keys(snap.scaleScores || {}).length ? `
      <div class="mb-6">
        <h3 class="font-extrabold text-slate-900 mb-3 flex items-center gap-2"><i class="fa-solid fa-chart-simple text-emerald-700"></i> الدرجات على المقاييس الفرعية</h3>
        <div class="grid sm:grid-cols-3 gap-3">
          ${(snap.scaleMeta || []).filter(s => s && s.key && !s.hidden && snap.scaleScores[s.key] !== undefined).map(s => `
            <div class="rounded-xl border border-slate-200 bg-white p-4">
              <p class="text-xs font-bold text-slate-800">${escapeHtml(s.ar || s.key)}</p>
              <p class="font-en text-[10px] text-slate-400">${escapeHtml(s.en || s.key)}</p>
              <p class="text-xl font-extrabold text-emerald-800 mt-2" dir="ltr">${Number(snap.scaleScores[s.key]).toFixed(Number.isInteger(snap.scaleScores[s.key]) ? 0 : 1)}</p>
            </div>`).join('')}
        </div>
      </div>` : ''}

    <div class="grid sm:grid-cols-2 gap-4 mb-6 avoid-break">
      <div class="rounded-xl border border-emerald-200 bg-emerald-50/60 p-5">
        <h3 class="font-extrabold text-emerald-900 mb-3 text-sm flex items-center gap-2"><i class="fa-solid fa-circle-check"></i> نقاط القوة</h3>
        <ul class="space-y-2">
          ${narrative.strengths.map(s => `<li class="text-xs leading-relaxed text-slate-700 flex gap-2"><i class="fa-solid fa-check text-emerald-700 mt-0.5"></i><span>${escapeHtml(s)}</span></li>`).join('')}
        </ul>
      </div>
      <div class="rounded-xl border border-amber-200 bg-amber-50/60 p-5">
        <h3 class="font-extrabold text-amber-900 mb-3 text-sm flex items-center gap-2"><i class="fa-solid fa-circle-exclamation"></i> نقاط الضعف</h3>
        <ul class="space-y-2">
          ${narrative.weaknesses.map(s => `<li class="text-xs leading-relaxed text-slate-700 flex gap-2"><i class="fa-solid fa-minus text-amber-700 mt-0.5"></i><span>${escapeHtml(s)}</span></li>`).join('')}
        </ul>
      </div>
    </div>

    <div class="avoid-break mb-6 rounded-xl border border-slate-200 bg-slate-50 p-5">
      <h3 class="font-extrabold text-slate-900 mb-3 text-sm flex items-center gap-2"><i class="fa-solid fa-list-check text-emerald-700"></i> التوصيات</h3>
      <ol class="space-y-2 list-decimal list-inside">
        ${narrative.recommendations.map(s => `<li class="text-xs leading-relaxed text-slate-700">${escapeHtml(s)}</li>`).join('')}
      </ol>
    </div>

    <div class="avoid-break">
      <h3 class="font-extrabold text-slate-900 mb-3">تفصيل البنود</h3>
      <div class="overflow-x-auto rounded-xl border border-slate-200">
        <table class="w-full min-w-[620px] text-right text-xs">
          <thead class="bg-slate-50 text-slate-500 border-b border-slate-200">
            <tr><th class="py-2 px-3">#</th><th class="py-2 px-3">البند</th><th class="py-2 px-3">الاستجابة</th><th class="py-2 px-3">الدرجة</th></tr>
          </thead>
          <tbody>
            ${items.map(i => `
              <tr class="border-b border-slate-100">
                <td class="py-2 px-3 font-bold text-slate-500">${escapeHtml(i.position)}</td>
                <td class="py-2 px-3 text-slate-700">${escapeHtml(i.textAr || i.textEn || '')}</td>
                <td class="py-2 px-3 text-slate-600">${escapeHtml(i.chosenAr || i.chosenEn || '')}</td>
                <td class="py-2 px-3 font-extrabold text-emerald-800">${escapeHtml(i.score)}</td>
              </tr>`).join('')}
          </tbody>
        </table>
      </div>
    </div>

    ${r.clinical_notes ? `
      <div class="avoid-break mb-6 rounded-xl border border-indigo-200 bg-indigo-50/60 p-5">
        <h3 class="font-extrabold text-indigo-900 mb-2 text-sm flex items-center gap-2"><i class="fa-solid fa-note-sticky"></i> ملاحظات إكلينيكية</h3>
        <p class="text-xs leading-relaxed text-slate-700 whitespace-pre-line">${escapeHtml(r.clinical_notes)}</p>
      </div>` : ''}

    ${r.review_status === 'approved' ? `
      <div class="avoid-break mb-6 rounded-xl border-2 border-emerald-200 bg-emerald-50 p-4 flex items-center gap-3">
        <i class="fa-solid fa-circle-check text-emerald-700"></i>
        <p class="text-xs font-bold text-emerald-900">معتمد من ${escapeHtml(r.reviewed_by_name || 'متخصص')} ${r.reviewed_at ? '• ' + formatDate(r.reviewed_at, true) : ''}</p>
      </div>` : ''}

    <div class="grid grid-cols-2 gap-8 text-center text-xs text-slate-700 mt-10 pt-6 border-t border-slate-200 avoid-break">
      <div><p class="font-bold mb-8">توقيع الأخصائي النفسي</p><div class="w-48 mx-auto border-b border-dashed border-slate-400"></div></div>
      <div><p class="font-bold mb-8">اعتماد المشرف الأكاديمي</p><div class="w-48 mx-auto border-b border-dashed border-slate-400"></div></div>
    </div>`;

  renderReportStatus(r, !!r.narrative);
  document.getElementById('report-modal').classList.remove('hidden');
}

function renderReportStatus(report, hasCustomNarrative) {
  const badge = document.getElementById('report-status-badge');
  const approved = report.review_status === 'approved';
  badge.textContent = approved ? 'معتمد' : 'مسودة';
  badge.className = `text-[10px] font-bold rounded-full px-2 py-1 ${approved ? 'bg-emerald-100 text-emerald-800' : 'bg-slate-100 text-slate-600'}`;
  document.getElementById('approve-report-btn').classList.toggle('hidden', approved);
  document.getElementById('reset-report-btn').classList.toggle('hidden', !hasCustomNarrative);
}

function reportNarrative(report) {
  return report.narrative || buildClinicalNarrative(report);
}

function linesToArray(value) {
  return String(value || '').split(/\r?\n/).map(s => s.trim()).filter(Boolean);
}

function startReportEdit() {
  const report = state.reports.find(x => x.id === state.currentReportId);
  if (!report) return;
  const narrative = reportNarrative(report);
  document.getElementById('edit-diagnosis').value = narrative.diagnosis || '';
  document.getElementById('edit-strengths').value = (narrative.strengths || []).join('\n');
  document.getElementById('edit-weaknesses').value = (narrative.weaknesses || []).join('\n');
  document.getElementById('edit-recommendations').value = (narrative.recommendations || []).join('\n');
  document.getElementById('edit-notes').value = report.clinical_notes || '';
  document.getElementById('report-modal-body').classList.add('hidden');
  document.getElementById('report-edit-panel').classList.remove('hidden');
}

async function saveReportEdit() {
  const report = state.reports.find(x => x.id === state.currentReportId);
  if (!report) return;
  try {
    const narrative = {
      diagnosis: document.getElementById('edit-diagnosis').value.trim(),
      strengths: linesToArray(document.getElementById('edit-strengths').value),
      weaknesses: linesToArray(document.getElementById('edit-weaknesses').value),
      recommendations: linesToArray(document.getElementById('edit-recommendations').value)
    };
    const { error } = await sb.from('reports').update({
      narrative,
      clinical_notes: document.getElementById('edit-notes').value.trim(),
      review_status: 'draft',
      reviewed_by: null,
      reviewed_by_name: '',
      reviewed_at: null
    }).eq('id', report.id);
    if (error) throw error;
    Object.assign(report, {
      narrative,
      clinical_notes: document.getElementById('edit-notes').value.trim(),
      review_status: 'draft',
      reviewed_by: null,
      reviewed_by_name: '',
      reviewed_at: null
    });
    openReport(report.id);
    toast('تم حفظ التقرير');
  } catch (e) {
    toast(errorMessage(e), 'error');
  }
}

async function resetReportNarrative() {
  const report = state.reports.find(x => x.id === state.currentReportId);
  if (!report) return;
  try {
    const { error } = await sb.from('reports').update({
      narrative: null,
      review_status: 'draft',
      reviewed_by: null,
      reviewed_by_name: '',
      reviewed_at: null
    }).eq('id', report.id);
    if (error) throw error;
    Object.assign(report, {
      narrative: null,
      review_status: 'draft',
      reviewed_by: null,
      reviewed_by_name: '',
      reviewed_at: null
    });
    openReport(report.id);
    toast('تم استرجاع الصياغة الآلية وإعادة التقرير للمسودة');
  } catch (e) {
    toast(errorMessage(e), 'error');
  }
}

async function approveReport() {
  const report = state.reports.find(x => x.id === state.currentReportId);
  if (!report) return;
  try {
    const now = new Date().toISOString();
    const { error } = await sb.from('reports').update({
      review_status: 'approved',
      reviewed_by: state.profile?.id || null,
      reviewed_by_name: state.profile?.full_name || 'متخصص',
      reviewed_at: now
    }).eq('id', report.id);
    if (error) throw error;
    Object.assign(report, {
      review_status: 'approved',
      reviewed_by: state.profile?.id || null,
      reviewed_by_name: state.profile?.full_name || 'متخصص',
      reviewed_at: now
    });
    openReport(report.id);
    toast('تم اعتماد التقرير');
  } catch (e) {
    toast(errorMessage(e), 'error');
  }
}

function renderAssessments() {
  document.getElementById('assessments-list').innerHTML = state.assessments.map(a => `
    <div class="rounded-2xl border ${a.active ? 'border-emerald-200 bg-emerald-50/40' : 'border-slate-200 bg-slate-50'} p-5">
      <div class="flex items-start justify-between gap-3 mb-3">
        <div>
          <h4 class="font-extrabold text-slate-900">${escapeHtml(a.title_ar)}</h4>
          <p class="font-en text-[11px] font-bold text-emerald-700 mt-0.5">${escapeHtml(a.title_en)}</p>
        </div>
        <span class="text-[10px] font-bold rounded-full px-2 py-1 ${a.active ? 'bg-emerald-100 text-emerald-800' : 'bg-slate-200 text-slate-600'}">${a.active ? 'مفعّل' : 'متوقف'}</span>
      </div>
      <span class="inline-block text-[10px] font-bold rounded-full px-2 py-1 mb-2 ${a.suite === 'special' ? 'bg-amber-100 text-amber-800' : 'bg-sky-100 text-sky-800'}">${escapeHtml(SUITE_LABELS[a.suite] || SUITE_LABELS.clinical)}</span>
      <p class="text-xs text-slate-500 leading-relaxed mb-4">${escapeHtml(a.description_ar || '')}</p>
      <div class="flex items-center justify-between pt-3 border-t border-slate-200/70">
        <span class="text-[11px] text-slate-500 font-en">v${escapeHtml(a.version)} • ${escapeHtml(a.slug)}</span>
        <div class="flex flex-wrap gap-2">
          ${a.active ? `<button data-issue-code="${escapeHtml(a.id)}" class="text-[11px] font-bold text-emerald-800 hover:text-emerald-950 rounded focus-ring min-h-[44px] px-2" aria-label="إصدار رقم دخول لـ ${escapeHtml(a.title_ar)}"><i class="fa-solid fa-key ml-1" aria-hidden="true"></i> رقم دخول</button>` : ''}
          <button data-toggle-assessment="${escapeHtml(a.id)}" data-active="${a.active}" class="text-[11px] font-bold text-slate-700 hover:text-emerald-800 rounded focus-ring min-h-[44px] px-2">${a.active ? 'إيقاف' : 'تفعيل'}</button>
          <button data-edit-assessment="${escapeHtml(a.id)}" class="text-[11px] font-bold text-emerald-800 rounded focus-ring min-h-[44px] px-2">تعديل</button>
        </div>
      </div>
    </div>`).join('') || '<p class="col-span-full py-10 text-center text-sm text-slate-400">لا توجد اختبارات. أضف اختباراً جديداً.</p>';

  document.querySelectorAll('[data-edit-assessment]').forEach(btn => {
    btn.addEventListener('click', () => openAssessmentEditor(state.assessments.find(a => a.id === btn.dataset.editAssessment)));
  });
  document.querySelectorAll('[data-issue-code]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const select = document.getElementById('access-code-assessment');
      select.value = btn.dataset.issueCode;
      await issueAccessCode(btn.dataset.issueCode);
    });
  });
  document.querySelectorAll('[data-toggle-assessment]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const { error } = await sb.from('assessments').update({ active: btn.dataset.active !== 'true' }).eq('id', btn.dataset.toggleAssessment);
      if (error) toast(errorMessage(error), 'error');
      else { toast('تم تحديث حالة الاختبار'); loadAssessments(); }
    });
  });
}

function renderSettings() {
  document.getElementById('settings-form').innerHTML = SETTING_FIELDS.map(([key, label]) => `
    <div>
      <label class="field-label">${escapeHtml(label)}</label>
      <textarea class="field" rows="2" data-setting="${escapeHtml(key)}">${escapeHtml(state.settings[key] || '')}</textarea>
    </div>`).join('');
}

function renderItemsEditor() {
  const host = document.getElementById('items-editor');
  host.innerHTML = state.editorItems.map((item, idx) => `
    <div class="rounded-xl border border-slate-200 bg-slate-50 p-4" data-item-row="${idx}">
      <div class="flex items-center justify-between mb-3">
        <span class="text-xs font-extrabold text-slate-700">البند ${idx + 1}</span>
        <div class="flex items-center gap-2">
          <button type="button" data-item-up="${idx}" class="text-slate-400 hover:text-emerald-700"><i class="fa-solid fa-arrow-up"></i></button>
          <button type="button" data-item-down="${idx}" class="text-slate-400 hover:text-emerald-700"><i class="fa-solid fa-arrow-down"></i></button>
          <button type="button" data-item-delete="${idx}" class="text-rose-500 hover:text-rose-700"><i class="fa-solid fa-trash"></i></button>
        </div>
      </div>
      <div class="grid sm:grid-cols-3 gap-3 mb-3">
        <div><label class="field-label">الترتيب</label><input class="field" data-ifield="position" data-idx="${idx}" type="number" value="${escapeHtml(item.position)}" /></div>
        <div><label class="field-label">المجال (للمتخصص)</label><input class="field" data-ifield="domain_ar" data-idx="${idx}" value="${escapeHtml(item.domain_ar || '')}" /></div>
        <div><label class="field-label">عنوان البند (للمتخصص)</label><input class="field" data-ifield="title_ar" data-idx="${idx}" value="${escapeHtml(item.title_ar || '')}" /></div>
      </div>
      <div class="grid sm:grid-cols-2 gap-3 mb-3">
        <div><label class="field-label">نص البند (عربي)</label><textarea class="field" rows="2" data-ifield="text_ar" data-idx="${idx}">${escapeHtml(item.text_ar || '')}</textarea></div>
        <div><label class="field-label">Item text (English)</label><textarea class="field" rows="2" data-ifield="text_en" data-idx="${idx}">${escapeHtml(item.text_en || '')}</textarea></div>
      </div>
      <div class="grid sm:grid-cols-2 gap-3 mb-3">
        <div><label class="field-label">صورة البند (اختياري)</label><input class="field font-en" dir="ltr" data-ifield="image_url" data-idx="${idx}" value="${escapeHtml(item.image_url || '')}" placeholder="assets/raven/A01.png" /></div>
        <div><label class="field-label">المقاييس (JSON: [{"key":"E","direction":"positive"}])</label><textarea class="field font-en" dir="ltr" rows="2" data-ifield="scales" data-idx="${idx}">${escapeHtml(prettyJson(item.scales || []))}</textarea></div>
      </div>
      <div><label class="field-label">الخيارات (JSON: [{"score":0,"ar":"...","en":"..."}])</label>
        <textarea class="field font-en" dir="ltr" rows="4" data-ifield="options" data-idx="${idx}">${escapeHtml(prettyJson(item.options))}</textarea>
      </div>
    </div>`).join('') || '<p class="text-sm text-slate-400 text-center py-4">لا توجد بنود. أضف بنداً جديداً.</p>';

  host.querySelectorAll('[data-ifield]').forEach(el => {
    el.addEventListener('change', () => {
      const idx = Number(el.dataset.idx);
      const field = el.dataset.ifield;
      state.editorItems[idx][field] = field === 'position' ? Number(el.value) : el.value;
    });
  });
  host.querySelectorAll('[data-item-delete]').forEach(btn => btn.addEventListener('click', () => {
    state.editorItems.splice(Number(btn.dataset.itemDelete), 1);
    renderItemsEditor();
  }));
  host.querySelectorAll('[data-item-up]').forEach(btn => btn.addEventListener('click', () => {
    const i = Number(btn.dataset.itemUp);
    if (i > 0) [state.editorItems[i - 1], state.editorItems[i]] = [state.editorItems[i], state.editorItems[i - 1]];
    renderItemsEditor();
  }));
  host.querySelectorAll('[data-item-down]').forEach(btn => btn.addEventListener('click', () => {
    const i = Number(btn.dataset.itemDown);
    if (i < state.editorItems.length - 1) [state.editorItems[i + 1], state.editorItems[i]] = [state.editorItems[i], state.editorItems[i + 1]];
    renderItemsEditor();
  }));
}

async function openAssessmentEditor(assessment) {
  state.editing = assessment || null;
  document.getElementById('assessment-modal-title').textContent = assessment ? `تعديل: ${assessment.title_ar}` : 'اختبار جديد';

  setTextValue('a-slug', assessment?.slug || '');
  setTextValue('a-version', assessment?.version || '1.0');
  setTextValue('a-title-ar', assessment?.title_ar || '');
  setTextValue('a-title-en', assessment?.title_en || '');
  setTextValue('a-patient-ar', assessment?.patient_label_ar || '');
  setTextValue('a-patient-en', assessment?.patient_label_en || '');
  setTextValue('a-suite', assessment?.suite || 'clinical');
  setTextValue('a-category', assessment?.category || 'clinical');
  setTextValue('a-sort', assessment?.sort_order ?? 10);
  setTextValue('a-desc-ar', assessment?.description_ar || '');
  setTextValue('a-instructions-ar', assessment?.instructions_ar || '');
  setTextValue('a-cutoffs', prettyJson(assessment?.cutoffs || []));
  setTextValue('a-rules', prettyJson(assessment?.critical_rules || []));
  setTextValue('a-scale-meta', prettyJson(assessment?.scale_meta || []));
  document.getElementById('a-active').checked = assessment ? assessment.active : true;

  if (assessment) {
    const { data, error } = await sb.from('assessment_items').select('*').eq('assessment_id', assessment.id).order('position');
    if (error) { toast(errorMessage(error), 'error'); return; }
    state.editorItems = (data || []).map(i => ({ ...i }));
  } else {
    state.editorItems = [{
      position: 1, domain_ar: '', domain_en: '', title_ar: '', title_en: '',
      text_ar: '', text_en: '', image_url: '', scales: [],
      options: [{ score: 0, ar: '', en: '' }, { score: 1, ar: '', en: '' }]
    }];
  }
  renderItemsEditor();
  document.getElementById('assessment-modal').classList.remove('hidden');
}

function setTextValue(id, value) {
  const el = document.getElementById(id);
  if (el) el.value = value ?? '';
}

function parseJsonField(id, label) {
  const raw = document.getElementById(id).value.trim() || '[]';
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new Error('يجب أن تكون القائمة مصفوفة JSON');
    return parsed;
  } catch (e) {
    throw new Error(`صيغة ${label} غير صحيحة: ${e.message}`);
  }
}

async function saveAssessment() {
  try {
    const cutoffs = parseJsonField('a-cutoffs', 'حدود التصنيف');
    const rules = parseJsonField('a-rules', 'قواعد التنبيهات');
    const scaleMeta = parseJsonField('a-scale-meta', 'مقاييس التصحيح');

    const payload = {
      slug: document.getElementById('a-slug').value.trim(),
      version: document.getElementById('a-version').value.trim() || '1.0',
      title_ar: document.getElementById('a-title-ar').value.trim(),
      title_en: document.getElementById('a-title-en').value.trim(),
      patient_label_ar: document.getElementById('a-patient-ar').value.trim(),
      patient_label_en: document.getElementById('a-patient-en').value.trim(),
      suite: document.getElementById('a-suite').value,
      category: document.getElementById('a-category').value,
      sort_order: Number(document.getElementById('a-sort').value) || 0,
      description_ar: document.getElementById('a-desc-ar').value.trim(),
      instructions_ar: document.getElementById('a-instructions-ar').value.trim(),
      cutoffs,
      critical_rules: rules,
      scale_meta: scaleMeta,
      active: document.getElementById('a-active').checked
    };
    if (!payload.slug || !payload.title_ar) throw new Error('المعرّف والعنوان مطلوبان');

    let assessmentId = state.editing?.id;
    if (assessmentId) {
      const { error } = await sb.from('assessments').update(payload).eq('id', assessmentId);
      if (error) throw error;
    } else {
      const { data, error } = await sb.from('assessments').insert(payload).select('id').single();
      if (error) throw error;
      assessmentId = data.id;
    }

    const itemRows = state.editorItems.map((item, idx) => ({
      id: item.id || undefined,
      assessment_id: assessmentId,
      position: Number(item.position) || idx + 1,
      domain_ar: String(item.domain_ar || ''),
      domain_en: String(item.domain_en || ''),
      title_ar: String(item.title_ar || ''),
      title_en: String(item.title_en || ''),
      text_ar: String(item.text_ar || ''),
      text_en: String(item.text_en || ''),
      image_url: String(item.image_url || ''),
      options: typeof item.options === 'string' ? JSON.parse(item.options) : item.options,
      scales: typeof item.scales === 'string' ? JSON.parse(item.scales) : (item.scales || [])
    }));

    const keptIds = itemRows.filter(r => r.id).map(r => r.id);
    if (state.editing) {
      const { data: existing, error: fetchError } = await sb.from('assessment_items').select('id').eq('assessment_id', assessmentId);
      if (fetchError) throw fetchError;
      const removed = (existing || []).map(x => x.id).filter(id => !keptIds.includes(id));
      if (removed.length) {
        const { error } = await sb.from('assessment_items').delete().in('id', removed);
        if (error) throw error;
      }
    }

    const { error: itemsError } = await sb.from('assessment_items').upsert(itemRows, { onConflict: 'id' });
    if (itemsError) throw itemsError;

    document.getElementById('assessment-modal').classList.add('hidden');
    toast('تم حفظ الاختبار بنجاح');
    await loadAssessments();
    renderDashboard();
  } catch (e) {
    toast(errorMessage(e), 'error');
  }
}

async function saveSettings() {
  try {
    const rows = [...document.querySelectorAll('[data-setting]')].map(el => ({
      key: el.dataset.setting,
      value: JSON.stringify(el.value)
    }));
    const { error } = await sb.from('app_settings').upsert(rows, { onConflict: 'key' });
    if (error) throw error;
    await loadSettings();
    toast('تم حفظ الإعدادات');
  } catch (e) {
    toast(errorMessage(e), 'error');
  }
}

async function authorize() {
  const { data: { user } } = await sb.auth.getUser();
  if (!user) { showLogin(); return; }

  const { data, error } = await sb.from('specialists').select('*').eq('id', user.id).eq('active', true).maybeSingle();
  if (error || !data) {
    if (error) console.warn(error);
    toast('هذا الحساب غير مخول بالدخول للوحة المتخصص', 'error');
    await sb.auth.signOut();
    showLogin();
    return;
  }

  state.profile = data;
  state.isAdmin = data.role === 'admin';
  state.isDemo = (data.email || user.email) === 'demo@menoufia.edu.eg';
  setText('user-label', `${data.full_name || user.email} ${state.isDemo ? '• عرض تجريبي' : state.isAdmin ? '• مدير' : ''}`);
  document.getElementById('add-team-card').classList.add('hidden');
  document.getElementById('show-team-btn').classList.toggle('hidden', !state.isAdmin);
  document.getElementById('demo-banner').classList.toggle('hidden', !state.isDemo);
  showApp();

  try {
    await Promise.all([loadAssessments(), loadReports(), loadSettings(), loadTeam(), loadAccessCodes()]);
  } catch (e) {
    toast(errorMessage(e), 'error');
  }
}

function friendlyAuthError(error) {
  const message = errorMessage(error).toLowerCase();
  if (message.includes('invalid login credentials')) return 'البريد الإلكتروني أو كلمة المرور غير صحيحة. جرّب زر «دخول تجريبي» أعلاه.';
  if (message.includes('email not confirmed')) return 'لم يتم تأكيد البريد الإلكتروني بعد.';
  if (message.includes('too many requests')) return 'محاولات كثيرة؛ انتظر قليلاً ثم حاول مجدداً.';
  return errorMessage(error);
}

async function signIn(email, password, err) {
  err.classList.add('hidden');
  try {
    const { error } = await sb.auth.signInWithPassword({ email, password });
    if (error) throw error;
    await authorize();
  } catch (e) {
    err.textContent = friendlyAuthError(e);
    err.classList.remove('hidden');
  }
}

function bindEvents() {
  document.getElementById('login-form').addEventListener('submit', async e => {
    e.preventDefault();
    const email = document.getElementById('login-email').value.trim();
    const password = document.getElementById('login-password').value;
    await signIn(email, password, document.getElementById('login-error'));
  });

  document.getElementById('demo-login-btn').addEventListener('click', async () => {
    document.getElementById('login-email').value = 'demo@menoufia.edu.eg';
    document.getElementById('login-password').value = 'Demo@2026';
    await signIn('demo@menoufia.edu.eg', 'Demo@2026', document.getElementById('login-error'));
  });

  document.getElementById('reset-demo-btn').addEventListener('click', async () => {
    const btn = document.getElementById('reset-demo-btn');
    btn.disabled = true;
    try {
      const { data, error } = await sb.rpc('seed_demo_data');
      if (error) throw error;
      await Promise.all([loadAssessments(), loadReports(), loadSettings(), loadTeam(), loadAccessCodes()]);
      toast(`تمت إعادة ضبط ${data?.demoReports ?? 0} تقريراً تجريبياً`);
    } catch (e) {
      toast(errorMessage(e), 'error');
    } finally {
      btn.disabled = false;
    }
  });

  document.getElementById('logout-btn').addEventListener('click', async () => {
    await sb.auth.signOut();
    state.isDemo = false;
    document.getElementById('demo-banner').classList.add('hidden');
    showLogin();
  });

  document.querySelectorAll('[data-tab]').forEach(btn => {
    btn.addEventListener('click', () => {
      switchTab(btn.dataset.tab);
      if (btn.dataset.tab === 'assessments') loadAccessCodes();
    });
  });

  document.getElementById('issue-code-btn').addEventListener('click', () =>
    issueAccessCode(document.getElementById('access-code-assessment')?.value));
  document.getElementById('access-code-close-btn').addEventListener('click', closeAccessCodeModal);
  document.getElementById('access-code-copy-btn').addEventListener('click', async () => {
    const code = document.getElementById('access-code-value').textContent.trim();
    try {
      await navigator.clipboard.writeText(code);
      toast('تم نسخ رقم الدخول');
    } catch { toast('تعذر النسخ، يمكنك تحديد الرقم يدوياً', 'error'); }
  });
  setupDialog(document.getElementById('access-code-modal'), openAccessCodeModal, closeAccessCodeModal);
  setupDialog(
    document.getElementById('report-modal'),
    () => {},
    () => document.getElementById('report-modal').classList.add('hidden')
  );
  setupDialog(
    document.getElementById('assessment-modal'),
    () => {},
    () => document.getElementById('assessment-modal').classList.add('hidden')
  );

  document.getElementById('report-search').addEventListener('input', renderReports);
  document.getElementById('report-filter').addEventListener('change', renderReports);
  document.getElementById('close-report-btn').addEventListener('click', () => document.getElementById('report-modal').classList.add('hidden'));
  document.getElementById('print-report-btn').addEventListener('click', () => window.print());
  document.getElementById('edit-report-btn').addEventListener('click', startReportEdit);
  document.getElementById('cancel-report-btn').addEventListener('click', () => {
    document.getElementById('report-edit-panel').classList.add('hidden');
    document.getElementById('report-modal-body').classList.remove('hidden');
  });
  document.getElementById('save-report-btn').addEventListener('click', saveReportEdit);
  document.getElementById('reset-report-btn').addEventListener('click', resetReportNarrative);
  document.getElementById('approve-report-btn').addEventListener('click', approveReport);
  document.getElementById('report-modal').addEventListener('click', e => {
    if (e.target.id === 'report-modal') document.getElementById('report-modal').classList.add('hidden');
  });

  document.getElementById('add-assessment-btn').addEventListener('click', () => openAssessmentEditor(null));
  document.getElementById('close-assessment-btn').addEventListener('click', () => document.getElementById('assessment-modal').classList.add('hidden'));
  document.getElementById('cancel-assessment-btn').addEventListener('click', () => document.getElementById('assessment-modal').classList.add('hidden'));
  document.getElementById('save-assessment-btn').addEventListener('click', saveAssessment);
  document.getElementById('add-item-btn').addEventListener('click', () => {
    state.editorItems.push({
      position: state.editorItems.length + 1, domain_ar: '', domain_en: '',
      title_ar: '', title_en: '', text_ar: '', text_en: '',
      options: [{ score: 0, ar: '', en: '' }, { score: 1, ar: '', en: '' }]
    });
    renderItemsEditor();
  });

  document.getElementById('save-settings-btn').addEventListener('click', saveSettings);

  document.getElementById('show-team-btn').addEventListener('click', () => document.getElementById('add-team-card').classList.remove('hidden'));
  document.getElementById('cancel-team-btn').addEventListener('click', () => document.getElementById('add-team-card').classList.add('hidden'));
  document.getElementById('save-team-btn').addEventListener('click', async () => {
    try {
      const { error } = await sb.rpc('create_specialist_account', {
        p_email: document.getElementById('new-team-email').value.trim(),
        p_password: document.getElementById('new-team-password').value,
        p_full_name: document.getElementById('new-team-name').value.trim(),
        p_role: document.getElementById('new-team-role').value
      });
      if (error) throw error;
      document.getElementById('add-team-card').classList.add('hidden');
      document.getElementById('new-team-email').value = '';
      document.getElementById('new-team-password').value = '';
      document.getElementById('new-team-name').value = '';
      toast('تم إنشاء الحساب');
      loadTeam();
    } catch (e) {
      toast(errorMessage(e), 'error');
    }
  });

  document.getElementById('change-password-btn').addEventListener('click', async () => {
    const password = document.getElementById('new-password').value;
    if (password.length < 6) { toast('كلمة المرور قصيرة جداً', 'error'); return; }
    const { error } = await sb.auth.updateUser({ password });
    if (error) toast(errorMessage(error), 'error');
    else { toast('تم تحديث كلمة المرور'); document.getElementById('new-password').value = ''; }
  });
}

bindEvents();
sb.auth.onAuthStateChange((event, session) => {
  if (event === 'SIGNED_OUT') showLogin();
  else if (session && event !== 'INITIAL_SESSION') authorize();
});
authorize();
