# Publishing on Steam — No Safe Orbit (publisher: TheBooleanJulian)

What the repository already does for a Steam release, and the steps that
need the Steamworks account (they involve logins, payment and tax details,
so they are done by hand and nothing about them is stored here).

Steam's terms, fees, waiting periods and asset sizes change. The figures
below were right as of mid-2026; check them on the Steamworks partner site
(partner.steamgames.com) before relying on them.

## Ready in the repository

| Item | Where |
|---|---|
| Version `0.12.0` (the last finished milestone, M12) | `project.godot` → `application/config/version`; shown in the credits |
| Executable metadata: company **TheBooleanJulian**, product **No Safe Orbit**, © 2026 TheBooleanJulian | `export_presets.cfg` (Windows) |
| Windows and Linux (x86_64) export presets | `export_presets.cfg` |
| Credits and every licence in game: F1 → **Credits & licences** | `scripts/app/credits.gd`, `scripts/ui/controls_panel.gd` |
| The same as `THIRD_PARTY_NOTICES.txt` beside the executable (Godot's MIT licence must ship with the game) | `tools/write_notices.gd`, called by `tools/steam_export.sh` |
| UI scales with the window from a 1600 × 900 base (`canvas_items`, `expand`); rendered and checked at 1280 × 800 (Steam Deck) and 2560 × 1440 | `project.godot` → `display/window/stretch` |
| Fullscreen toggle, remembered (F11, rebindable) | `scripts/app/display_settings.gd`, `user://settings.cfg` |
| Depot build script and steamcmd templates | `tools/steam_export.sh`, `steam/*.vdf` |
| No network access, no accounts, no telemetry | (nothing in `scripts/` opens a connection) |
| Tests: version, presets, credits for every data source, F1 credits view, fullscreen setting | `tests/unit/test_release.gd` |

Not in the repository, on purpose: the Steamworks SDK (achievements, rich
presence, the overlay API, stats). It would mean a native GDExtension
dependency (GodotSteam) and an app ID in the build; it is a separate
decision. Steam itself works without it — the overlay, Steam Input, Cloud
(Auto-Cloud, below) and playtime all do.

## 1. The Steamworks account

1. Sign up at partner.steamgames.com as **TheBooleanJulian** — as a company
   if TheBooleanJulian is registered as one, otherwise as an individual
   with TheBooleanJulian as the developer and publisher name shown on the
   store.
2. Complete the bank, tax (Valve's tax interview sets the US withholding
   rate) and identity steps.
3. Pay the Steam Direct fee for one app (US$100, recouped after US$1,000
   of gross revenue). Steam asks new developers to wait 30 days after
   paying before the first release.

## 2. The app

1. Create the app; note its **App ID**. Create two depots (Windows,
   Linux); by default the script assumes App ID + 1 and + 2 — pass
   `STEAM_WIN_DEPOT_ID` / `STEAM_LINUX_DEPOT_ID` if Steam gave others.
2. Installation → General: launch options
   - Windows: executable `NoSafeOrbit.exe`
   - Linux (and Steam Deck native): executable `NoSafeOrbit.x86_64`
3. Steam Cloud → **Auto-Cloud** (no SDK needed). Saves live in Godot's
   user folder:

   | Root | Subdirectory | Pattern | Recursive |
   |---|---|---|---|
   | `WinAppDataRoaming` | `Godot/app_userdata/No Safe Orbit` | `profile.json*` | no |
   | `WinAppDataRoaming` | `Godot/app_userdata/No Safe Orbit/blueprints` | `*.json` | no |
   | `WinAppDataRoaming` | `Godot/app_userdata/No Safe Orbit` | `*.cfg` | no |

   Add a root override for Linux: `WinAppDataRoaming` →
   `LinuxXdgDataHome`, with the subdirectory `godot/app_userdata/No Safe Orbit`.
   Leave out `logs/`, `debriefs/`, `backups/` and `shader_cache/`.
   The save folder is deliberately not moved (it would orphan existing
   saves).
4. Depots → Linux depot: mark it for Linux + SteamOS.

## 3. Build and upload

One-off: install Godot's export templates for 4.7.2 (Editor → Manage
Export Templates → Download and Install). They are not installed on the
development machine yet, so the executables themselves have not been
exported or launched here — only the data pack, which `tools/run_checks.sh`
exports and boots on every run.

```bash
GODOT=/c/Software/Godot_v4.7.2-stable_win64.exe STEAM_APP_ID=<app id> bash tools/steam_export.sh
```

This exports both platforms into `build/steam/windows` and
`build/steam/linux` (each with `THIRD_PARTY_NOTICES.txt`) and writes the
filled-in steamcmd scripts to `build/steam/scripts/`. Before uploading,
launch `build/steam/windows/NoSafeOrbit.exe` once and fly a sortie. Then
upload with Valve's steamcmd (from the Steamworks SDK download), logging
in with your own build account:

```bash
steamcmd +login <your_steam_build_account> +run_app_build "<repo>/build/steam/scripts/app_build.vdf" +quit
```

The build arrives unpublished. In Steamworks → Builds, set it live on a
`beta` branch first, install it through Steam, play it, then set it live
on `default`.

## 4. Steam Deck

- The UI scales to 1280 × 800 (checked by render) and every flight action
  has a gamepad default except the keyboard-only ones: missiles and
  missile mode, countermeasures, the target cycle, the grapple, alert
  acknowledge, the help, orbit and details panels, the orbit camera, the
  tutorial, fullscreen and mouse release. Steam Input can
  map those to the Deck's back buttons and trackpads; publish a default
  Steam Input layout that does.
- Expect **Playable**, not **Verified**: Verified needs every action and
  text entry reachable without a keyboard and the default layout to show
  gamepad glyphs.

## 5. Store page

Required before the "Coming Soon" page can go live (the page must be
public for at least two weeks before release, and both the page and the
build are reviewed by Valve, a few working days each).

### Text

**Short description** (≤ 300 characters):

> A hard-sci-fi ship engineering and combat simulator. Design a warship
> block by block, then fly and fight it in real-scale Earth and lunar
> orbit — where armour, power, heat and crew decide how it fails, and
> every round you miss keeps orbiting.

**About this game:**

> Your ship's construction decides how it flies, how it fights, how it
> fails, and whether it survives.
>
> Build in the shipyard from hull blocks and sloped wedges, paint on
> armour, route power, place reactors, radiators, guns, missile pods,
> hangars and crew quarters. Then take it into a 400 km Earth orbit or a
> 100 km lunar orbit under the real sky — the stars, Sun, Moon and Earth
> where they actually are.
>
> - **Newtonian flight in real orbits.** Every ship, round and missile
>   obeys orbital mechanics; a miss keeps flying and may come back round.
> - **Penetration, not hit points.** Rounds punch through armour and wreck
>   what lies behind it: reactors, gun mounts, crew, coolant.
> - **A crew that works the ship.** Fight fires, seal breaches, reroute
>   power, send boarders through a docked gangway.
> - **Missiles, point defence, flares and jamming.** Salvos, EMP and
>   nuclear warheads; decoys and electronic warfare to answer them.
> - **Fighters, interceptors, bombers and drones** that fly the same
>   physics, with orders you give.
> - **Salvage and refit.** Disable, board and strip enemies; keep your
>   damage between sorties; buy destroyers, cruisers and carriers.

**Tags (up to 20):** Space Sim, Simulation, Spaceships, Building,
Physics, Sci-fi, Realistic, Tactical, Strategy, Combat, Singleplayer,
Sandbox, Space, Hard Sci-Fi (if available), Indie.

**Mature-content survey:** fictional spacecraft combat; no gore, no
depiction of people being harmed beyond crew counts; no in-game purchases;
no user-generated content shared online.

**Languages:** English (interface; there is no voice acting).

**Controller support:** partial (see §4).

**System requirements (minimum, to be confirmed by testing on lower-end
hardware):** Windows 10 64-bit or a recent 64-bit Linux; a Vulkan
1.1-capable GPU (Godot's Forward+ renderer); 8 GB RAM; 300 MB disk.
Measured reference: RTX 3060 Ti, Ryzen 7 5800X — 77 fps average (p95
20 ms) in the big-fight benchmark (`tools/profile_frames.gd`: three enemy
ships, fighters, missile salvos, every round simulated).

### Images

Make these from in-game renders (the capture tools in `tools/` save
1600 × 900; re-render at 1920 × 1080 for the store). Sizes as Valve listed
them in 2026 — confirm on Steamworks → Store Page → Graphical Assets:

| Asset | Size (px) |
|---|---|
| Header capsule | 920 × 430 |
| Small capsule | 462 × 174 |
| Main capsule | 1232 × 706 |
| Vertical capsule | 748 × 896 |
| Page background (optional) | 1438 × 810 |
| Screenshots (at least 5) | 1920 × 1080 |
| Library capsule | 600 × 900 |
| Library header | 920 × 430 |
| Library hero | 3840 × 1240 |
| Library logo (transparent) | 1280 × 720 |
| Client and community icons | 32 × 32 .ico, 184 × 184 .jpg |

Capsules must show the game's name and art only — no review quotes or
award text.

## 6. Open decisions (yours)

- **Icon**: the game has no application icon yet (the untracked
  `icon.svg` in the working folder is yours and was not used). Once
  chosen, set `config/icon` in `project.godot` and an `.ico` in the
  Windows preset's `application/icon`.
- **Version scheme**: `0.12.0` follows the milestones; there is no release
  or tagging policy yet.
- **Early Access or full release**, price and regional pricing, release
  date.
- **Steamworks SDK** (achievements etc.): needs approval for the
  GodotSteam dependency.
- **macOS**: not prepared (needs code signing and notarisation with an
  Apple developer account).
