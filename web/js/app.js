// Petites aides côté client : totaux en direct, lignes, messages d'erreur.
const eur = new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' });
const r2 = (x) => Math.round((x + Number.EPSILON) * 100) / 100;

function recalc() {
  const form = document.getElementById('devis-form');
  if (!form) return;
  let ht = 0, tva = 0;
  form.querySelectorAll('tr.ligne').forEach((tr) => {
    const q = parseFloat(tr.querySelector('[name=ligne_quantite]').value) || 0;
    const pu = parseFloat(tr.querySelector('[name=ligne_prix]').value) || 0;
    const t = parseFloat(tr.querySelector('[name=ligne_tva]').value) || 0;
    const lht = r2(q * pu);
    ht += lht;
    tva += r2(q * pu * t / 100);
    tr.querySelector('.ligne-total').textContent = eur.format(lht);
  });
  document.getElementById('t-ht').textContent = eur.format(ht);
  document.getElementById('t-tva').textContent = eur.format(tva);
  document.getElementById('t-ttc').textContent = eur.format(ht + tva);
}

function supprimerLigne(btn) {
  const tbody = btn.closest('tbody');
  if (tbody.querySelectorAll('tr.ligne').length > 1) btn.closest('tr').remove();
  recalc();
}

function toast(msg) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toast.t);
  toast.t = setTimeout(() => el.classList.remove('show'), 5000);
}

document.addEventListener('input', (e) => { if (e.target.closest('#devis-form')) recalc(); });
document.addEventListener('change', (e) => { if (e.target.closest('#devis-form')) recalc(); });
document.addEventListener('htmx:afterSettle', recalc);

// Nouvelle ligne : place le curseur dessus
document.addEventListener('htmx:afterSwap', (e) => {
  if (e.detail.target && e.detail.target.id === 'lignes') {
    const rows = e.detail.target.querySelectorAll('tr.ligne');
    rows[rows.length - 1].querySelector('input').focus();
  }
});

// Erreurs PostgREST (JSON {message}) -> message lisible
document.addEventListener('htmx:responseError', (e) => {
  let msg = 'Erreur ' + e.detail.xhr.status;
  try { msg = JSON.parse(e.detail.xhr.responseText).message || msg; } catch (_) {}
  toast(msg);
});
document.addEventListener('htmx:sendError', () => toast('Serveur injoignable : la stack Docker est-elle démarrée ?'));
