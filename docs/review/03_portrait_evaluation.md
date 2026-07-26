# Omertà RP — Newspaper Portrait Pipeline Evaluation (P-001)

Commissioned evaluation of five approaches for the black-and-white victim/subject portraits in newspaper articles (GDD §14, Tech §20). Selection criteria set by the project lead: **technical reliability, low maintenance cost, consistent results.** Perfect realism is explicitly not required for MVP.

## Technical background (what Garry's Mod actually permits)

Three engine facts decide most of this evaluation:

1. **Servers cannot render.** A dedicated server has no renderer, so any *captured* image must be produced on a client, then uploaded.
2. **There is no runtime file distribution.** Content downloads (FastDL/Workshop) happen at connect time. An image captured mid-season must be pushed to every current and future client through chunked `net` messages (≈64 KB per message, manual chunking, ordering, and caching in each client's `data/` folder) and re-served to every client who joins later — a small custom CDN living inside the gamemode, forever.
3. **Clients can render deterministically.** Any client can render a character model with chosen bodygroups/skins/materials into a render target with fixed pose, lighting, and post-processing. Given the same inputs, every client produces the same picture.

Fact 3 is the escape hatch: **if the server stores the *description* of a face rather than a *picture* of it, every client can reconstruct an identical portrait locally, on demand, forever** — including in the cross-season archive. The character-creation flow already captures appearance descriptors (Tech §2, roadmap M4), so the input data exists by design.

## Option analysis

### Option A — No photograph, text only
- **Reliability/maintenance/consistency:** perfect, trivially.
- **Cost:** loses a signature immersion beat. The B&W portrait next to "MARIO SANTINO FOUND DEAD" is one of the strongest images in the whole concept (BA §7), and the library archive loses most of its texture.
- **Verdict:** rejected as the baseline; acceptable only as the final fallback when nothing is known.

### Option B — Generic silhouette
- **Reliability/maintenance/consistency:** perfect; a handful of static assets.
- **Cost:** all victims look alike; no archive identity. But as a *meaningful state* — "no public photograph of this person existed" — it is diegetically correct and cheap.
- **Verdict:** adopt as the standard fallback tier, not the standard.

### Option C — Mugshot captured at character creation
- **Mechanism:** client renders its own character in a controlled "photo booth" at creation; uploads via chunked net messages; server stores and redistributes.
- **Reliability:** moderate — upload can fail/disconnect mid-transfer; server must validate that the blob is a plausible image (clients can lie about pixels: uploaded content is untrusted and could be arbitrary imagery, requiring moderation tooling).
- **Maintenance:** the highest of all options: chunk protocol, server-side blob storage in the DB/filesystem, redistribution to every joining client, cache invalidation, archive storage growth across seasons.
- **Consistency:** good (controlled booth), but only as good as the upload pipeline.
- **Verdict:** the best *captured* option, but it buys visual fidelity MVP doesn't need at the price of a permanent content-distribution subsystem and a player-content moderation surface. Post-MVP candidate.

### Option D — Client-generated portrait captured on death
- **Mechanism:** as C, but captured at death time by some client.
- **Reliability:** poor — *whose* client? The killer's? The victim's (possibly disconnected)? Captured mid-ragdoll, masked, bloodied, in the dark? Every one of those is an inconsistency or an information leak (a masked corpse photo that reveals the face model violates the file-photo rule in Tech §20).
- **Verdict:** rejected. Worst of every axis except novelty.

### Option E — Composite portrait rendered from appearance data
- **Mechanism:** the server stores only the appearance snapshot already captured at creation (model, skin, bodygroups, outfit descriptors — small structured data). When any client needs a portrait (newspaper, archive), it renders the character model locally in a standardized pose and lighting into a render target, applies a grayscale/grain/halftone "newsprint" post-process, and caches the result. Same inputs → same portrait on every client, every session, every season.
- **Reliability:** high — no upload, no storage, no redistribution, no player-supplied pixels; the only failure mode is a missing model, which falls back to Option B.
- **Maintenance:** low — one client-side renderer + the snapshot schema; archive cost is a few hundred bytes per character instead of image blobs.
- **Consistency:** excellent, and the aged-newsprint styling *benefits* from the model-render look — "police sketch / file photo" is the diegetic register a period paper wants.
- **Information safety:** portraits derive from the *stored* public appearance, not live state — a masked killer's article can't leak an unmasked face unless the paper legitimately has one (file-photo rule enforced by data, not discipline).
- **Verdict: recommended.**

## Recommendation

| Tier | When | Approach |
|---|---|---|
| Standard | Public appearance data exists for an identified subject | **E — composite render from appearance snapshot** |
| Fallback | Subject identified but no adequate public appearance data | **B — silhouette** ("no photograph was available") |
| Final fallback | Unidentified subject | **A — text only / "person unknown"** |
| Post-MVP enhancement | If higher fidelity is ever wanted | **C — creation-booth mugshot**, layered on top without schema changes |

Concrete consequences already reflected in the roadmap:

- M4 (Characters) must freeze an **appearance snapshot schema** at creation — spike S2 validates the renderer against it before that schema ships.
- M21 (Newspaper) implements the tiered logic above; no image pipeline milestone exists anywhere.

**Status: RECOMMENDED (P-001), awaiting project-lead confirmation.**
