(() => {
  const cfg = window.STASHBAR_CONFIG || {};
  const form = document.getElementById('fb');
  const status = document.getElementById('status');
  let kind = 'bug';

  document.querySelectorAll('.kind').forEach(btn => btn.addEventListener('click', () => {
    kind = btn.dataset.kind;
    document.querySelectorAll('.kind').forEach(b => b.setAttribute('aria-pressed', String(b === btn)));
  }));

  form.addEventListener('submit', async e => {
    e.preventDefault();
    const message = document.getElementById('msg').value.trim();
    const email = document.getElementById('email').value.trim();
    const env = document.getElementById('env').checked ? `${navigator.userAgent}`.slice(0, 500) : null;
    if (!message) { status.textContent = 'Tell us what happened first.'; document.getElementById('msg').focus(); return; }

    if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) {
      // No backend configured: hand off to a prefilled GitHub issue.
      const title = `[${kind}] ${message.split('\n')[0].slice(0, 70)}`;
      const body = `${message}\n\n${email ? `Reply to: ${email}\n` : ''}${env ? `Env: ${env}` : ''}`;
      location.href = `https://github.com/${cfg.repo || 'sajidur7/stash-bar'}/issues/new?title=${encodeURIComponent(title)}&body=${encodeURIComponent(body)}`;
      return;
    }

    status.textContent = 'Sending…';
    try {
      const res = await fetch(`${cfg.supabaseUrl.replace(/\/$/, '')}/rest/v1/feedback`, {
        method: 'POST',
        headers: { apikey: cfg.supabaseAnonKey, Authorization: `Bearer ${cfg.supabaseAnonKey}`, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify({ kind, message, email: email || null, app_info: env }),
      });
      if (!res.ok) throw new Error(String(res.status));
      form.reset();
      status.textContent = 'Thanks — we read every message.';
    } catch {
      status.textContent = 'Couldn’t send right now. Please try again, or open a GitHub issue.';
    }
  });
})();
