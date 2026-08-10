# BuildSpy

Spy, save and reproduce other players' builds on **Project Ascension**
(Wildcard / Character Advancement realms). See a build you like? Grab it,
study it, share it — and rebuild it on your own character in two clicks.

![Main window](screenshots/main-window.png)

## Grab any player's build

A **Grab** button sits right on the inspection window (`/ains` on your target
does the same). One click captures the player's full Character Advancement
build — spells, talents and their chosen **Path** — plus their equipped gear
and identity, into your local database.

![Grab button](screenshots/grab-button.png)

**+ My build** (bottom of the builds window) or `/ains self` grabs your own
character, Path included.

## Browse everything

`/ains builds` — or the minimap button — opens the main window:

- **Left**: every grabbed build with its Path icon, 1H/2H, name, spec,
  comment and date. Sortable by Name, Date or Path; hover a row for the full
  detail; add a comment per build.
- **Right**: the build's spells and talents — required level, type, and
  **rarity read from the actual Skill Cards** (uncollected ones included).
  Default sort: rarity, legendary first. The **Ignore** checkbox excludes an
  entry from every export below.

## Gear & stats

**Show gear** slides out a side pane: the real equipped items (tooltips show
enchants) and the summed stats of the whole set.

![Gear pane](screenshots/gear-pane.png)

## Share builds as plain text

**Export** produces a paste-anywhere text version of the build — header,
Path, spells and talents sorted by rarity then level, and the gear as exact
`itemID:enchantID` pairs. **Import** reads one back, unknown names reported.
A toggle chooses whether ignored entries ship too.

**Link** copies a shareable `ascension.nie.one` build link (base-36 spell
ids) — paste it in guild chat or a browser and the build opens on the site.

Import accepts **three formats**: a BuildSpy text export, an
`ascension.nie.one` link, or the site's comma-separated spell-id list — any
of them lands as a build in your list.

![Export dialog](screenshots/export-dialog.png)

## Reproduce builds

- **→ Skill Cards** — optimizes and **places your Skill Cards** for the
  selected build: golden pools first, rarest cards first, starters = the
  build's level-1 spells, never a duplicate, verified slot by slot.

![Skill Cards](screenshots/skill-cards.png)

- **→ Rapid Roll** — pushes the build into Rapid Rolling's **Desired
  Spells** list (verified entry by entry) and marks everything you already
  know that is NOT in the build as undesired, ready to reroll.

![Rapid Roll](screenshots/rapid-roll.png)

Both buttons open the matching client window first, and the addon reminds
you in chat to double-check the result yourself.

## Commands

| Command | Effect |
| --- | --- |
| `/ains` | Grab the inspected/targeted player |
| `/ains builds` | Toggle the builds window |
| `/ains self` | Grab your own build |
| `/ains list` | Chat summary of the database |
| `/ains clear` | Purge all captures |

## Installation

1. Download the latest version (Code → Download ZIP).
2. Extract the `BuildSpy` folder into `Interface\AddOns\` so you end up with
   `Interface\AddOns\BuildSpy\BuildSpy.toc`.
3. Restart the game client (a full restart, not a `/reload`).

No dependencies — works standalone. A draggable minimap button toggles the
builds window (the *minimap button* checkbox in the window hides it).

## License

[MIT](LICENSE)
