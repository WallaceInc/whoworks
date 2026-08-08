# Deploying whoworks.app to Cloudflare Pages

Domain is registered at GoDaddy. Registration stays there — only DNS moves to
Cloudflare, which is free and is what lets Pages serve the bare apex domain.

## 1. Add the domain to Cloudflare

1. [dash.cloudflare.com](https://dash.cloudflare.com) → **Add a domain** → `whoworks.app`
2. Choose the **Free** plan
3. Cloudflare scans existing DNS and shows two nameservers, e.g.
   `xxx.ns.cloudflare.com` / `yyy.ns.cloudflare.com`

## 2. Point GoDaddy at them

GoDaddy → **My Products** → `whoworks.app` → **DNS** → **Nameservers** →
**Change** → **I'll use my own nameservers** → paste both Cloudflare ones.

Propagation is usually minutes, occasionally a few hours. Cloudflare emails you
when the zone goes active.

## 3. Upload the site

1. Cloudflare dash → **Workers & Pages** → **Create** → **Pages** →
   **Upload assets**
2. Project name: `whoworks`
3. Drag the **contents** of this `docs/` folder in — not the folder itself.
   The upload should show `index.html` at the top level, plus `privacy/`,
   `support/`, `icon.png`, `screenshot.png`.
4. **Deploy**

You get a preview at `whoworks.pages.dev`. Check it before wiring the domain.

## 4. Attach the domain

Project → **Custom domains** → **Set up a custom domain** → `whoworks.app`

Add `www.whoworks.app` too if you want it; Cloudflare will redirect it.

Cloudflare creates the DNS records and issues the certificate automatically.
This matters: **`.app` is an HTTPS-only TLD**, HSTS-preloaded into every
browser, so the site is unreachable without a valid certificate. Give it a few
minutes before testing.

## 5. Verify before submitting to Apple

These three must load over HTTPS with no warning:

- https://whoworks.app
- https://whoworks.app/privacy
- https://whoworks.app/support

App Review does check that the privacy policy URL resolves.

## Updating later

Same project → **Create deployment** → drag the folder again. Or run
`npx wrangler pages deploy docs --project-name=whoworks` from the repo root.

## Structure

Each page is a folder with an `index.html`, so `/privacy` and `/support` work
on any static host without extension-guessing. Assets are referenced from the
root (`/icon.png`), which is why the pages can live one level down.
