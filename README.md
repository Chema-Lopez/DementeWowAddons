# Demente's WoW addons

This repository contains four independent World of Warcraft (retail) addons. Each folder is copied as is into `World of Warcraft\_retail_\Interface\AddOns\`.

## Installation

1. Download the repository: green **Code → Download ZIP** button.
2. Unzip it. Inside there is one folder per addon: `SimpleTransmogWishlist`, `TransmogAtlas`, `AutoChannelLeaver` and `MountAtlas`.
3. Copy the folders of the addons you want into `World of Warcraft\_retail_\Interface\AddOns\`. Each folder must sit directly inside `AddOns` (for example `AddOns\TransmogAtlas\TransmogAtlas.toc`), not inside an extra folder.
4. If the game was running, quit and start it again (`/reload` does not load new addons).
5. On the character select screen, open **AddOns** and check that they are enabled.

To update: replace the addon folder with the new one. Saved data (SavedVariables) is kept.

None of them is on CurseForge, so CurseForge will not install or update them.

The in-game texts are in English, with a Spanish (Spain, `esES`) translation picked automatically from the client language.

## Simple Transmog Wishlist (`SimpleTransmogWishlist/`)

A list of transmog appearances you want to get.

- You add items by ID and the addon checks whether you already know the appearance.
- It looks up the sources of each appearance (where it drops / which boss) using `C_TransmogCollection`.
- Its own window to see the list, reorder it and remove entries.
- Data is saved in `STW_DB` (SavedVariables).

| Command | What it does |
|---|---|
| `/stw add <itemID>` | Adds an item to the list |
| `/stw del <itemID>` | Removes it from the list |
| `/stw ui` | Opens/closes the window |
| `/stw refresh` | Resolves pending sources again |
| `/stw help` | Help |

## AutoChannelLeaver (`AutoChannelLeaver/`)

Automatically leaves the chat channels you choose on every character of the account. By default it leaves **Trade** and **Services**; **General**, **Local Defense**, **Looking For Group** and **Newcomer Chat** can be turned on as well.

- The settings are account-wide (`AutoChannelLeaverDB`): what you check applies to every character, including new ones.
- It acts when you log in and whenever the channel list changes.
- Channels are recognised by name on English and Spanish clients.
- Unchecking a channel does not join it again: use `/join <channel>` once.
- Formerly **Sin Comercio**: if you had it installed, delete the `SinComercio` folder.

| Command | What it does |
|---|---|
| `/acl` | Opens the options (Options → AddOns → AutoChannelLeaver) |
| `/acl list` | Lists the channels you are in, their `zoneChannelID` and whether they will be left |

## TransmogAtlas (`TransmogAtlas/`) — working title

Scans the loot of every dungeon and raid in the Adventure Guide and shows your transmog collection % by expansion, instance, difficulty and boss, for all classes or filtered by one.

### How it works

1. **Scan (once per patch).** Reads the loot of each instance and difficulty in one go (without selecting boss by boss) and stores every piece with an appearance: its `sourceID`, type (armor/weapon/slot) and which bosses drop it.
   - Runs in the background with a per-frame time budget and a limited duty cycle, so you can keep playing.
   - Pauses by itself in combat or while the Adventure Guide is open, and leaves the Adventure Guide filters as they were.
   - Resumable: after a `/reload` or logging out, `/tma scan` continues where it left off.
   - An instance can belong to several Adventure Guide expansions (e.g. "Current Season" lists Mythic+ dungeons from earlier expansions): its loot is stored once and the expansion membership separately.
   - Detects when the game version changes and warns that a rescan is recommended.
2. **Percentages.** Computed from the stored data by querying the collection (`C_TransmogCollection.GetAppearanceInfoBySource`) with a cache. It does not touch the Adventure Guide.
   - **Only the exact piece counts.** If you have the look from another piece it is marked separately (question mark) but counts as missing. Pieces the game grants automatically (e.g. lower-difficulty variants of a set) count as collected.
   - **Class filter:** all, yours or any class. Decided by armor/weapon type (`Classes.lua`) and by the class restriction of the transmog set the piece belongs to (`classMask`), which is what marks single-class set pieces.
   - **Difficulty filter:** all, Raid Finder, Normal, Heroic or Mythic.
3. **Adventure Guide–style UI.** Expansions on the left with their progress bar; pick one to see its raids and dungeons as cards with the Adventure Guide artwork; click an instance to see its detail by difficulty and boss with what is missing. Item names are loaded with `Item:ContinueOnItemLoad` and the list updates by itself.
4. **Weekly lockouts (0.4).** Reads which instances each character is saved to (`GetSavedInstanceInfo`) and which bosses are dead per difficulty (`C_RaidLocks.IsEncounterComplete`, the same the Adventure Guide uses). Stored per character, so each difficulty's tooltip says which alts still have it free.
5. **What should I run? (0.4).** Ranking of instance + difficulty by pieces you can still get this week (bosses already killed do not count), with the class and difficulty filters and checkboxes for raids/dungeons.
6. **Instance summary on entering (0.4).** Small movable window with what is missing in that difficulty boss by boss and which bosses are dead. Click it to open the main window on that instance.
7. **New piece message (0.4).** When you learn a scanned piece, the chat shows the new % of that instance and difficulty (grouped if several arrive at once).
8. **Search and addon button (0.4).** Search instances, bosses and pieces by name; TransmogAtlas appears in the addon compartment button next to the minimap.
9. **Options and language (0.4).** **Options** button: language (automatic, English or Español; instance, boss and item names come from the game and stay in the client language), instance summary, new piece messages and the minimap button (it can be dragged around the minimap).
10. **Old 10/25 raids (0.4).** In Cataclysm and Mists of Pandaria both sizes drop the same pieces and share a lockout: they are shown together as "Heroic (10/25)". In Wrath of the Lich King they are different pieces and stay separate. This is decided by comparing the scanned data. World boss groups do not appear in "What should I run?".

### Commands

| Command | What it does |
|---|---|
| `/tma` | Opens/closes the window |
| `/tma scan [fast]` | Scans or continues (`fast` = more aggressive, for leaving it AFK) |
| `/tma stop` | Stops the scan |
| `/tma rescan` | Wipes the data and scans from scratch |
| `/tma overlay` | Toggles the instance summary on entering |
| `/tma notify` | Toggles the new piece message |
| `/tma lockouts` | Instances the character is saved to |
| `/tma lang [auto\|en\|es]` | Addon language |
| `/tma minimap` | Shows/hides the minimap button |
| `/tma probe [id] [diff]` | Scans a single instance with detailed logging (no id: the current one) |
| `/tma verify [id] [diff]` | Compares the class filter with Blizzard's class filter |
| `/tma log [n]` | Last log lines |
| `/tma errors` | Stored errors |
| `/tma perf` | Metrics from the game's addon profiler |
| `/tma debug` | Debug messages in chat |

### Debugging

- Everything ends up in `WTF/Account/<account>/SavedVariables/TransmogAtlas.lua` → `TransmogAtlasLog` (log with timestamp and level, errors with stack trace and counter, performance metrics). It is written on `/reload` or logout.
- Work slices longer than 40 ms are logged as a warning with the step they were in.
- `/tma probe` and `/tma verify` let you investigate a single instance without scanning everything.

### Development notes

- Code, comments and log are in English; in-game texts go through `Locale.lua` (English by default, `esES` translation).
- API checked against the generated documentation of build 12.1.5 (70448): https://github.com/Gethe/wow-ui-source (`live` branch).
- In WoW's Lua you cannot `coroutine.yield` inside `pcall`/`xpcall`: long tasks are not wrapped in `xpcall`; operations that do not yield (such as processing one item) are protected.
- To do: item tooltip info, per-class tier sets (tokens), pets/toys, wishlist integration.

## MountAtlas (`MountAtlas/`)

Your mount collection laid out like [Simple Armory](https://simplearmory.com), inside the game: every mount by expansion or theme and by how it is obtained, with your % and how to get each one.

- **Groups** on the left (each expansion, plus Racial, Professions, PvP, World Events, Promotion, Limited Time…) with their progress bar, after "What should I farm?", "Favorites" and the holiday event, and with the weekly summary at the bottom.
- **Subcategories** as in Simple Armory (Achievement, Raid Drop, Reputation, Renown, Rare Spawn, Vendor, Quest, Treasure…), each with its bar and a grid of icons: collected in colour, missing greyed out, no longer obtainable with an orange border.
- **Tooltip:** collected or not, availability, faction, and the game's own "how to get it" text (vendor, zone and cost; boss and instance; achievement…) plus the mount description. Click an icon to open it in the Mount Journal.
- **Filters:**
  - *Sources:* achievement, raid, dungeon, reputation and renown, rare and world boss, vendor, quest, treasure and zone, PvP, world event, profession, class and race, shop and promotion, other activities. They apply across every expansion.
  - *Availability:* obtainable, limited time, no longer obtainable (off by default).
  - *Options:* show the other faction's mounts; hide the old promotion mounts that are now only sold on the Black Market Auction House (unless you have them).
  - *Only missing* and a name search.
- Percentages only count what the filters let through, and each mount once.
- Mounts in the game that Simple Armory does not list yet (a new patch, for example) appear under "Not in Simple Armory", grouped by the game's own source type.
- **Favorites:** right-click a mount to mark it; they are listed together under "Favorites".
- **Achievement mounts:** the tooltip shows the achievement and its criteria (done and missing). Ctrl-click opens it. The link between achievement and mount is the achievement's reward item.
- **Minimap button** that can be dragged around the minimap, plus the addon compartment entry.
- Settings are account-wide (`MountAtlasDB`).

**With [Rarity](https://www.curseforge.com/wow/addons/rarity) installed** (optional), MountAtlas also reads its data at runtime (nothing from Rarity is included in this repository):

- **Drop chance** on the icon of every missing mount Rarity knows, and in the tooltip: chance, difficulties, your attempts and how likely it was to have it by now.
- **Lockouts:** whether this character already killed the boss this lockout, and which of your other characters have it free or killed (each character is remembered after logging in with the addon; raids reset weekly, dungeons are taken as daily).
- **What should I farm?:** missing raid, dungeon, world boss and rare mounts with a known drop chance (world bosses and rares can be turned off in Options), up to the expansion you choose in Options (Shadowlands by default), best odds first and bosses already killed last. Each row has a **Take me** button.
- **Holiday event on now** (left panel, only while an event is on): its mounts you are missing, with the characters that already got today's reward.
- **Weekly summary** (left panel, or `/matlas semana`): mounts you got since the weekly reset (with character and date), this week's attempts per mount and in total, and your missing favorites with the characters where they are available or already killed.
- **Instance message:** when you enter an instance, the chat lists the mounts you are missing there with drop chance, difficulties, attempts and whether this character already killed the boss (can be turned off in Options).
- **Minimap tooltip:** your missing favorites with their type, drop chance and status for this character.
- **Waypoints:** Shift-click a mount (or **Take me**) to point to where it drops: TomTom's arrow if TomTom is installed, otherwise the game's map pin (which cannot be placed inside instances). When Rarity only knows the zone (roaming rares, for example), the button is **Show map** and opens the world map on that zone.

| Command | What it does |
|---|---|
| `/matlas` | Opens/closes the window (also from the addon compartment button) |
| `/matlas <text>` | Opens it searching for that name |
| `/matlas semana` | Opens the weekly summary |
| `/matlas minimap` | Shows/hides the minimap button |

**Mount data.** `MountAtlas/Data.lua` is generated from Simple Armory's [`mounts.json`](https://github.com/kevinclement/SimpleArmory/blob/master/static/data/mounts.json) by `tools/mountatlas_data.py`. After a patch, run `python tools/mountatlas_data.py` and commit the new file. The game does not expose vendor coordinates, exact reputation levels or quest chains, so the "how to get it" text is whatever the Mount Journal says.

## License

[MIT](LICENSE). The mount list in `MountAtlas/Data.lua` comes from [Simple Armory](https://github.com/kevinclement/SimpleArmory) by Kevin Clement, also MIT: see [`MountAtlas/LICENSE-SimpleArmory.txt`](MountAtlas/LICENSE-SimpleArmory.txt).
