import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

export const SUPABASE_URL = 'https://ylpgsstplbeldiafxsti.supabase.co';
export const SUPABASE_ANON_KEY = 'sb_publishable_SezpzFYmI5QTAbmi_4vfdA_K_l9M0h6';

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

export function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

export function unwrapSettings(value) {
  const out = {};
  Object.entries(value || {}).forEach(([key, v]) => {
    try {
      out[key] = typeof v === 'string' ? JSON.parse(v) : v;
    } catch {
      out[key] = v;
    }
  });
  return out;
}

export async function getSettings() {
  const { data, error } = await sb.rpc('get_public_settings');
  if (error) throw error;
  return unwrapSettings(data);
}

export function toast(message, type = 'success') {
  document.querySelectorAll('.toast').forEach(el => el.remove());
  const el = document.createElement('div');
  el.className = `toast ${type === 'error' ? 'bg-rose-700 text-white' : 'bg-emerald-800 text-white'}`;
  el.setAttribute('role', type === 'error' ? 'alert' : 'status');
  el.setAttribute('aria-live', type === 'error' ? 'assertive' : 'polite');
  el.textContent = message;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 3600);
}

export function errorMessage(error) {
  if (!error) return 'حدث خطأ غير متوقع';
  if (typeof error === 'string') return error;
  return error.message || 'حدث خطأ غير متوقع';
}

export function formatDate(value, withTime = false) {
  if (!value) return '—';
  try {
    const d = new Date(value);
    const date = new Intl.DateTimeFormat('ar-EG', {
      year: 'numeric', month: '2-digit', day: '2-digit'
    }).format(d);
    if (!withTime) return date;
    const time = new Intl.DateTimeFormat('ar-EG', {
      hour: '2-digit', minute: '2-digit'
    }).format(d);
    return `${date} • ${time}`;
  } catch {
    return String(value);
  }
}

export function setText(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = value ?? '';
}

// Keeps keyboard focus inside an open dialog and restores it on close.
export function setupDialog(modal, open, close) {
  if (!modal) return { open, close };
  const focusable = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
  modal.addEventListener('keydown', e => {
    if (e.key === 'Escape') { e.preventDefault(); close(); return; }
    if (e.key !== 'Tab') return;
    const items = [...modal.querySelectorAll(focusable)].filter(el => el.offsetParent !== null);
    if (!items.length) return;
    const first = items[0];
    const last = items[items.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  });
  return { open, close };
}
