# Play-test batch 11: task list

These are Julian's requests from the 2026-10-22 play-test, in the order given, grouped into the parts they ship in. Each line says whether it is done (with its PR) or still to do. The list is updated as work lands.

Legend: ✅ done · 🔧 in progress · ⬜ to do

## Promotion

- ✅ Promote dev to main (PR #70).

## Part 1: combat rules and craft (PR #71) ✅

- ✅ Remove the T toggle. Enemies become hostile automatically when fired on, or when they detect a locked-on player missile. Crafts don't count until they shoot.
- ✅ Each fighter or drone defaults to its role's optimal behaviour:
  - repair and salvage drones: Escort;
  - recon and EW drones: Recon;
  - interceptors: Intercept;
  - fighters and bombers: Strike.
- ✅ Fighters and drones return low on fuel, hull or ammo with enough safety margin not to get stranded (propellant for 1.5× the trip home).
- ✅ Fighters are more survivable, for both the player and enemies: twice the hull, and they break off earlier (70 / 50 / 30 % hull).
- ✅ All weapons have 3 tiers. Lasers are named by lasing medium: Yb-fibre (light), Nd:YAG (medium, the current one) and free-electron (heavy). Kinetic weapons already have 3 tiers.
- ✅ Fighters and drones carry only light-tier weapons, and target weak spots (the most damaged external system).
- ✅ Flares deploy one by one, round the ship, 0.25 s apart. The policy fires at most 3 per inbound missile.
- ✅ Flares have a trailing particle effect that dims after a few seconds, and a brighter glow while active.
- ✅ All hatches close during battle stations, so a breach doesn't vent other compartments.
- ✅ Crew spread through the ship by role, so a damaged room has someone to start repairs.
- ✅ C-key patching is automatic, with a notice of who is repairing what.

## Part 2: crew manifest ✅

- ✅ Rename "crew quarters" (the shipyard page) to "Crew manifest".
- ✅ At most 2 crew per crew-quarters cell. The count adjusts live with the refit bay's design.
- ✅ Crew are ship-agnostic: they move with you to the vessel you fly. Roles can still be reshuffled.
- ✅ Each crew member has a "previous occupation" (flavour only).
- ✅ More name permutations, with no duplicate names.
- ✅ The hiring hall sits in the top-right corner of the crew manifest page.
- ✅ Excess crew ("resting crew") stay at the shipyard on unpaid break, in a category below the hiring hall.
- ✅ The hiring hall never runs out, so large empty ships can be filled (Fill berths).
- ✅ New room type: crew armoury, the security crew's station.
- ✅ New room type: cafeteria, boosting crew skills by 2 % per cell.
- ✅ Refit bay: rename "Life support" to "Medbay".

## Part 3: refit bay ⬜

- ⬜ Dense magazine text uses the same colour as magazine (reddish).
- ⬜ Placed fighter cells use their text colour from the list. Use more colour variety: similar types (laser guns, laser drones, laser weapons) share a colour but have different shapes or icons.
- ⬜ All text colours match the cell colours in the refit bay.
- ⬜ Support 1×1 and 3×3 hull blocks, slopes and trusses.
- ⬜ Rename "power distribution" to "power distro".
- ⬜ Long equipment names in the palette display in full.
- ⬜ The top-down view shows the rendered parts instead of circles and rectangles.
- ⬜ Fix the 3×1 radiator panel's placement preview, which faces the wrong way (placing it works).
- ⬜ Hangars have one face (wall, ceiling or floor) exposed to the outside, which opens for fighter deployment.
- ⬜ Remove the opaque floor in the 3D view (or make the clamps taller), so the camera can look at the bottom of the ship.
- ⬜ Colour RCS blocks white; they blend into the armour now.

## Part 4: flight and shipyard ⬜

- ⬜ Atmospheric re-entry (Earth and Mars) shows a cone, not an ellipsoid.
- ⬜ The cargo hold lists the mission items in text.
- ⬜ With the ship-combat tab open, the hit cam doesn't block the centre, even with the orbit panel and combat log open.
- ⬜ Docking collar and gangway are octagonal: long edges with short corners, like a rounded, filleted square.
- ⬜ Found equipment in the cargo hold can be sold to the quartermaster.
- ⬜ The DEV credit button gives 100k credits.
- ⬜ Investigate the bug where banking cargo seems to fully repair the ship; fix it if it is one.
- ⬜ Ship dealer: pre-rendered, decorated catalogue images (to remove the load lag), in 3 columns instead of 2.

## Afterwards

- ⬜ Continue with the milestones. The agreed roadmap ended at Milestone 15; the next one is to be decided.
