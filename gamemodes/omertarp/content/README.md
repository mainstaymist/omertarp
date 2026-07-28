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
| `sound/omertarp/trombone-crescendo.wav` | 16-bit stereo PCM, 44.1 kHz, 0:22 | 3.8 MB | M19 — the moment of death |
| `sound/omertarp/death-piano.wav` | 16-bit stereo PCM, 44.1 kHz, 0:46 | 7.7 MB | M19 — the death screen, looped |

The two M19 sounds **are** registered (`modules/injury/sv_injury.lua`), because
that milestone plays them. The intro track is not, because M28 does not exist.

Open items for all three:

- **Format.** These are uncompressed. Together they are a 42 MB first-join
  download, most of it in front of a player who has not seen the game yet. MP3
  is the Source engine's native music format and would take the set to roughly
  6 MB. The WAVs are fine as masters; what ships to clients probably should not
  be. No encoder is available in this environment, so converting is a local
  step.
- **Licensing.** "Cry Me a River" (Arthur Hamilton, 1953) is a copyrighted
  composition and any recording carries its own rights. The two Freesound
  files are community uploads whose individual licences (CC0 / CC-BY /
  sampling+) need checking and, if attribution is required, recording. All
  three are acceptable development placeholders under D-005 and all three are
  a pre-release gate — see the roadmap's content workstream.
