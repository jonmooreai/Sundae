// The privacy page, served at /privacy by this same Worker, so there is no site to host.

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
<p class="muted">A photo dump app for a small group of friends and family, in testing.</p>

<h2>What Sundae keeps</h2>
<ul>
  <li>A private identifier from Sign in with Apple, so you can sign in again. Never your Apple ID email.</li>
  <li>Your name, username, bio and profile photo, if you add them.</li>
  <li>The photos you post on Sundays, their captions and alt text, and who you tag.</li>
  <li>Who you follow, your likes and comments, and the weekday ideas you mark done.</li>
  <li>Your time zone, so Sunday starts at your midnight.</li>
</ul>

<h2>What Sundae never collects</h2>
<ul>
  <li>Your location. Ideas near you are found on your phone with Apple Maps, and the weather comes from Open-Meteo for an area about a kilometer across. Neither lookup carries your account, and nothing about where you are reaches Sundae.</li>
  <li>Where your photos were taken. Location and camera details are removed on your phone before a photo is sent, and again when it arrives.</li>
  <li>Your contacts. Sundae never asks for them.</li>
  <li>Anything for ads or tracking. There are no ads, no analytics and no third-party trackers.</li>
</ul>

<h2>Who can see what</h2>
<p>Your weeks are visible to people you accept as followers, or to anyone if you make your account public. Photos are served through short-lived links. Nobody else, Sundae included, looks at your photos except to keep the service running.</p>

<h2>Where it lives</h2>
<p>On Cloudflare. Data is encrypted in transit and at rest.</p>

<h2>Deleting it</h2>
<p>Settings, then Delete account, removes your account, photos, comments, likes and tags right away. The database keeps a recovery history for 7 days, which only the person who runs Sundae can reach; after that, nothing of the account is left. Photos you were tagged in stay in the poster's week with your tag removed.</p>

<h2>Questions</h2>
<p>Send feedback from TestFlight and it reaches the person who runs Sundae.</p>
</main>
</body>
</html>
`;
