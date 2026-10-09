// Vercel build step: writes public runtime config for the feedback form.
// Set SUPABASE_URL and SUPABASE_ANON_KEY in Vercel → Project → Settings → Environment Variables.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const config = {
  supabaseUrl: process.env.SUPABASE_URL || '',
  supabaseAnonKey: process.env.SUPABASE_ANON_KEY || '',
  repo: process.env.GITHUB_REPO || 'sajidur7/stash-bar',
};
const out = fileURLToPath(new URL('../config.js', import.meta.url));
writeFileSync(out, `// Generated at build time.\nwindow.STASHBAR_CONFIG = ${JSON.stringify(config)};\n`);
console.log(`config.js written (feedback ${config.supabaseUrl ? '→ Supabase' : '→ GitHub issues fallback'})`);
