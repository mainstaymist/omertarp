# Gamemode content

Garry's Mod mounts `gamemodes/omertarp/content/` as if its subfolders sat in the
`garrysmod/` root. A file at

    gamemodes/omertarp/content/sound/omertarp/cry-me-a-river.wav

is addressed in code as

    omertarp/cry-me-a-river.wav

## Everything goes under an `omertarp/` subfolder

Sound, material and model paths are a **single global namespace** shared with the
base game and every mounted addon — the same problem M1 solved for database
tables with the `omerta_` prefix, for the same reason. A file dropped at
`sound/intro.wav` is one careless addon away from being silently replaced.

## Content is not automatically sent to clients

Mounting makes a file available to the *server*. A client only receives it if the
server calls `resource.AddFile("sound/omertarp/...")` — note the `sound/` prefix
here, which the playback path does not use.

**Register a file in the milestone that actually plays it, not when the asset
lands.** Every registered file is downloaded by every player on join, so
registering an asset ahead of the feature that needs it charges the whole player
base for something that does nothing.

## Inventory

| Path | Format | Size | Used by |
|---|---|---|---|
| `sound/omertarp/cry-me-a-river.wav` | 16-bit stereo PCM, 44.1 kHz, 2:55 | 30.9 MB | M28 (intro cinematic) — **not yet wired up** |

Two open items on that file, both for M28's design review:

- **Format.** 30.9 MB uncompressed is a long "downloading content" screen in front
  of the intro, which is the worst possible place for one. MP3 is the Source
  engine's native music format and the same track lands around 4 MB at 192 kbps.
  The WAV is fine as the master; what ships to clients probably should not be it.
- **Licensing.** "Cry Me a River" (Arthur Hamilton, 1953) is a copyrighted
  composition, and any recording of it carries its own rights. Acceptable as a
  development placeholder under D-005, but it needs a licence or a replacement
  before public release. Tracked in the roadmap's content workstream.
