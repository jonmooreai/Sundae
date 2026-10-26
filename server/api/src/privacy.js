// The privacy page, served at /privacy by this same Worker, so there is no site to host. The words
// come from Shared/privacy.json, the file the app's Privacy screen reads, so the two always agree.

import policy from '../../../Shared/privacy.json' with { type: 'json' };

const escape = (text) => String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const updated = new Intl.DateTimeFormat('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' })
  .format(new Date(`${policy.updated}T00:00:00Z`));

const sections = policy.sections.map((section) => `
<h2>${escape(section.title)}</h2>
<ul>
${section.items.map((item) => `  <li>${escape(item)}</li>`).join('\n')}
</ul>`).join('\n');

export const PRIVACY_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sundae privacy</title>
<style>
  :root { color-scheme: light dark; --bg: #fbf8f3; --ink: #1d1b18; --muted: #6b665e; }
  @media (prefers-color-scheme: dark) { :root { --bg: #191714; --ink: #f2eee8; --muted: #a39d94; } }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 17px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  main { max-width: 640px; margin: 0 auto; padding: 40px 20px 64px; }
  h1 { font-family: ui-serif, Georgia, serif; font-size: 34px; margin: 0 0 4px; }
  h2 { font-family: ui-serif, Georgia, serif; font-size: 21px; margin: 32px 0 6px; }
  p, li { margin: 6px 0; }
  .muted { color: var(--muted); }
</style>
</head>
<body>
<main>
<h1>Sundae privacy</h1>
<p>${escape(policy.summary)}</p>
<p class="muted">Updated ${escape(updated)}. The same words are in the app, under Settings, then Privacy.</p>
${sections}
</main>
</body>
</html>
`;
