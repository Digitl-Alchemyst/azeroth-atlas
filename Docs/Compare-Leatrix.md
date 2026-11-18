# Alchemy GPS vs Leatrix Maps — what Leatrix has that we don't

*Written 2026-11-18. Covers map features only (Leatrix Maps has no quest features).*

**How this was made.** I went through Leatrix Maps' options panels and code (`R:\addons\Leatrix_Maps`, the WoW Forever build), then searched our code for each feature. Anything we already do is left out. Each item was checked by searching our code, so a few could be wrong. If you spot one we already have, strike it.

**One thing to know first.** Leatrix changes **Blizzard's own world map**. We **replace** it with our own map, and Alt+M still opens Blizzard's. So some Leatrix features only make sense on Blizzard's map. Those are listed separately in section 4.

---

## 1. Features we don't have

### Points of interest

| # | Feature | What it does in Leatrix |
|---|---|---|
| 1.1 | ✅ *Done 2026-11-18.* **Portal icons** | Mage-city and other portals get their own icon and their own on/off switch. Ours has no Portals filter. A few portals are inside our zone-transition data, but nothing marks them as portals. |
| 1.2 | ✅ *Done 2026-11-18.* **Tram icons** | The Deeprun Tram stations are marked and shown with the boats and zeppelins. Ours has no tram icons. |
| 1.3 | ✅ *Done 2026-11-18.* **Show the other faction's points of interest** | A switch that also shows the other faction's flight points, boats, zeppelins and portals. Ours always hides the other faction's and has no switch. |
| 1.4 | ✅ *Done 2026-11-18.* **Click a travel icon to open where it goes** | Clicking a zone-exit arrow, portal, boat, zeppelin or tram opens the map of its destination. Ours only shows a tooltip. |
| 1.5 | ✅ *Done 2026-11-18.* **Click a dungeon entrance to open its map** | Clicking a dungeon or raid icon on a zone map opens that dungeon's map. If several dungeons share one icon, a small list pops up to pick from. Ours can only reach dungeon maps from the big map's Dungeons menu. |
| 1.6 | **Gamepad support** | With a controller, a crosshair picks the icon under it and shows its tooltip. Ours is mouse-only. |

### Unexplored areas

| # | Feature | What it does in Leatrix |
|---|---|---|
| 1.7 | **Switch to show or hide unexplored areas** | A checkbox for revealing unexplored areas. Ours always draws them dimmed; it's a fixed setting in the code (`SHOW_UNEXPLORED`). |
| 1.8 | **Tint colour and opacity for unexplored areas** | Red, green, blue and opacity sliders with a live preview square, so unexplored parts can be tinted any colour. Ours uses one fixed dim (35%). |

### Dungeon maps

| # | Feature | What it does in Leatrix |
|---|---|---|
| 1.9 | **Elite dragon and level badge on boss pins** | Boss portraits wear a gold dragon (elite), a silver ring (rare) or a grey dragon, plus a level number badge. Ours shows the portrait only; the level and "Rare" appear in the tooltip, not on the pin. |
| 1.10 | **Level drop-down list** | A menu button lists every level of the dungeon by name, and you click one to jump there. Ours has previous and next buttons only. |
| 1.11 | **Arrow keys to step through dungeon maps** | While previewing (`/ltm dun`), the arrow keys move to the next or previous dungeon and level. |
| 1.12 | **Right-click to see the normal map** | Right-clicking a dungeon map swaps back to the ordinary zone map until the map is next opened. |

### Themes

We have all 15 Leatrix themes. What we left out is the animated extras:

| # | Feature | What it does in Leatrix |
|---|---|---|
| 1.13 | **Retro TV power knob** | Clicking the top knob turns the TV off: the picture squeezes to a line, then a dot, then fades. Click again to turn it on. It plays click and hum sounds. |
| 1.14 | **Retro TV vertical-hold knob** | The second knob makes the picture roll, flicker and tear for a moment, with a burst of static. |
| 1.15 | **Handheld power button and boot screen** | The select button turns the handheld off and on, with a startup animation (four diamonds lock together with a flash) and startup sounds. |
| 1.16 | **Gem Match mini-game** | A full match-3 game played on the handheld's screen. It has special gems, combos, levels, hints, a best score and celebration effects. |

### Battlefield map (Shift+M)

| # | Feature | What it does in Leatrix |
|---|---|---|
| 1.17 | **Enhanced battlefield map** | Makes Blizzard's small battlefield map movable. It adds sliders for player arrow size, group icon size and map opacity, with a live preview, and hides the battlefield map's tab. We don't touch the battlefield map at all. |

### Settings and setup

| # | Feature | What it does in Leatrix |
|---|---|---|
| 1.18 | **Keybinding panel inside the addon** | Set keys from the addon's own settings: click, press a key, right-click to clear. This includes a key to open the settings panel. Ours uses Blizzard's Key Bindings screen and has no key for opening our settings. |
| 1.19 | **Own minimap button** | A button on the minimap that opens Leatrix's settings, with an option to hide it. Ours collects other addons' buttons into our dock but has no button of its own. |
| 1.20 | **Languages** | Translated into 9 languages, with a language picker in settings. Ours is English only. |
| 1.21 | **Reset button on every settings panel** | Each sub-panel has its own reset-to-default button. |

---

## 2. Things we partly have

| # | Feature | Leatrix | Ours |
|---|---|---|---|
| 2.1 | Zone levels on continent maps | Shows the level range on hover. The colour reflects your level, and zones well below you aren't yellow. | We show the level range and fishing skill under the cursor and in the Zones menu. Check whether ours colours by your level. |
| 2.2 | Coordinates | Player and cursor coordinates, with an optional dark background behind them. | We have player and cursor coordinates, but no background option. |
| 2.3 | Map scale | Separate scale sliders for the windowed and maximised map. | We resize the window instead; there's no scale slider. |
| 2.4 | Hide town and city icons | A switch to hide them on continent maps. | No switch. Check whether our continent view shows them at all. |

---

## 3. What we already match or beat (for balance)

- **Dungeon maps:** entrances, level-change arrows you can click, boss portraits, previewing dungeon maps from outside them, mouse-wheel zoom and drag-pan. Ours also adds quest pins inside dungeons.
- **Points of interest:** flight masters, boats, zeppelins, spirit healers, zone exits, dungeon entrances. Ours also adds innkeepers, mailboxes, bankers, auctioneers, guard directions, gathering nodes and treasure.
- **Map frame:** all 15 themes on either map, continent / zone / dungeon menus in the title bar, fishing levels.

---

## 4. Not relevant because we replace Blizzard's map

These Leatrix options change Blizzard's world map. Ours doesn't use that map, except when you press Alt+M.

- **Use simple map frame:** compact title bar; moves the quest log, search box and buttons around.
- **Hide blackout frame:** removes the dark screen behind the maximised map.
- **Disable map fade:** stops Blizzard's map fading while you move.
- **Hide filter reset button:** removes Blizzard's filter reset button.
- **Unlock and scale the map frame:** separate positions for the windowed and maximised map, kept on screen.

If you'd like Alt+M (Blizzard's map) to get any of these too, they'd be new work.
