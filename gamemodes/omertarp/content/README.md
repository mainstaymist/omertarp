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
| `sound/omertarp/confirm.wav` | 16-bit stereo PCM, 44.1 kHz, 0:01 | 0.2 MB | M19 — acknowledging the death screen |
| `sound/omertarp/ui/inventory-click.wav` | 16-bit stereo PCM, 44.1 kHz, 0.16 s | 27 KB | Hotbar switch click (`modules/weapons`) |
| `sound/omertarp/ui/searching-rustle.wav` | 16-bit mono PCM, 44.1 kHz, 0:30 | 2.7 MB | Timed searches — a random stretch is played per search (`modules/injury`) |
| `materials/omertarp/icons/icon_*.png` | PNG line art, ~150–250 KB each | 1.6 MB (9 files) | Inventory category icons (`modules/inventory`) |
| `resource/fonts/GermaniaOne-Regular.ttf` | TrueType | 33 KB | The game's face — every non-mono role (`modules/hud`) |
| `resource/fonts/IBMPlexMono-Regular.ttf` + `IBMPlexMono-Medium.ttf` | TrueType | ~129 KB each | The system voice: mono caps annotations (`modules/hud`) |

The three M19 sounds **are** registered (`modules/injury/sv_injury.lua`), because
that milestone plays them. The two UI sounds and the icons were supplied by the
project lead (2026-07-30) and are registered by the modules that use them.

**The intro track is still not registered by default.** The front end plays it,
which by the rule above would mean registering it — but it is 30.9 MB of
uncompressed WAV standing between a new player and their first impression, and
which format clients receive is an open M28 ruling. So it sits behind
`menu.send_music`, default **off**: anyone who already has the file (developers,
and any client with the gamemode mounted) hears it, and nobody else waits for
it. Turning it on before compressing it is the thing not to do.

Both typefaces are OFL; their licence files ship beside them. The style guide's
Oswald/Archivo pairing was tried in the field and rejected the same day —
Germania One is the game's face and returned, carrying all the guide's roles
except the mono system voice. Shipping unused fonts charges every player's
first join for nothing, so the rejected pair is gone rather than parked.

Open items for all three:

- **Format.** These are uncompressed. Together they are a 43 MB first-join
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
