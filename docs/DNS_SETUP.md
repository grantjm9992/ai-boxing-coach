# DNS setup — aicornerman.com

Domain registered at **arsys**; site to be hosted on **Railway**. Railway has no
static IP — everything is CNAME-based — so the only real wrinkle is the naked
(apex) domain. Two clean routes below; **Route B (Cloudflare) is recommended**
for a static marketing site because it fixes the apex *and* is free CDN + TLS.

---

## First: get the target from Railway

In Railway → your service → **Settings → Networking → Custom Domain**, add both
`aicornerman.com` and `www.aicornerman.com`. For each, Railway shows:
- a **CNAME target** like `xxxxxx.up.railway.app`, and
- sometimes a **TXT** verification record.

Copy those — you paste them into DNS below. Railway auto-issues a Let's Encrypt
cert once the records resolve.

> A static site technically needs a tiny static server on Railway (a `Caddy` or
> `serve` container). If that feels like overkill, a static host (Cloudflare
> Pages / Netlify / GitHub Pages) is free and simpler — but Route B below already
> gives you Cloudflare, which can host the static site directly via Pages if you
> later prefer.

---

## Route A — keep DNS at arsys (www is canonical)

arsys' standard zone editor can't put a CNAME on the apex, so make `www` the real
site and redirect the apex to it.

In the **arsys control panel → your domain → DNS / zone editor**:

| Type | Host / Name | Value | TTL |
|------|-------------|-------|-----|
| CNAME | `www` | `xxxxxx.up.railway.app` (Railway's target) | 3600 |
| TXT | (as shown) | (Railway's verification value) | 3600 |

Then for the apex `aicornerman.com` use arsys' **URL redirect / forwarding**
feature → forward to `https://www.aicornerman.com` (301, "keep path" if offered).

Canonical stays `https://aicornerman.com/` in the site — so if arsys forwarding
is reliable, prefer making the **apex** canonical and redirecting www→apex
instead. If arsys can't reliably forward the apex over HTTPS, switch the site's
canonical/OG to the `www` host to match reality.

---

## Route B — move DNS to Cloudflare (recommended)

Cloudflare does **CNAME flattening** at the apex, so the naked domain points
straight at Railway. You keep the domain registered at arsys; only its
nameservers change.

1. Create a free Cloudflare account → **Add site** `aicornerman.com`.
2. Cloudflare gives you two nameservers (e.g. `xxx.ns.cloudflare.com`).
3. In **arsys → your domain → nameservers/DNS**, replace arsys' nameservers with
   Cloudflare's. (Propagation: minutes to a few hours.)
4. In **Cloudflare → DNS**, add:

| Type | Name | Target | Proxy |
|------|------|--------|-------|
| CNAME | `@` | `xxxxxx.up.railway.app` | DNS only (grey cloud) first |
| CNAME | `www` | `xxxxxx.up.railway.app` | DNS only first |
| TXT | (as shown) | (Railway verification) | — |

   Start **"DNS only" (grey cloud)** so Railway can validate ownership and issue
   its cert. Once Railway shows the domain as active with a valid cert, you may
   switch the two records to **Proxied (orange cloud)** for Cloudflare's CDN — but
   then set Cloudflare **SSL/TLS mode = Full (strict)** to avoid a redirect loop.

---

## Verify

```bash
dig +short aicornerman.com
dig +short www.aicornerman.com
curl -sSI https://aicornerman.com | head -n1      # expect HTTP/2 200
curl -sSI https://www.aicornerman.com | head -n1
```

Both hostnames should serve the site over HTTPS with a valid cert. Then confirm
the share card renders: paste `https://aicornerman.com` into
https://cards-dev.twitter.com/validator or the Facebook Sharing Debugger — the
`assets/og.png` should appear (it's referenced absolutely now).

## Gotchas

- **Don't** add an A record — Railway publishes no static IP.
- Apex + `www` both need a record; a visitor typing either must work.
- After first setup, cert issuance can take a few minutes; a temporary "cert
  invalid" is normal until Railway finishes.
- Email: if you use `@aicornerman.com` email, moving nameservers to Cloudflare
  means re-adding your MX records there, or email breaks.
