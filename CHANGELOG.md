# Changelog

All notable changes to Alchemy GPS are logged here. Format is loose
(this is a solo/small-team addon project, not a public release train)
but entries are dated and grouped by area so the history stays
readable.

## Unreleased — 2026-11-10

### Map window
- Removed a leftover solid dark placeholder texture on the window's
  content frame (`MinimapWindow.lua`). It was a stand-in for the real
  world-art canvas from before build-order step 8 landed, never
  removed once real tiles existed, and was painting over the tile art
  every tick regardless of brightness — the actual cause of "brightness
  slider does nothing, map stays black."
- Minimap mask switched from Blizzard's round mask to a square one
  (`MinimapEngine.lua`). The live-rendered accent patch was only
  filling the inscribed circle while the static world-art background
  already filled the whole square content area; the round mask was the
  only thing cropping the live patch down.
- Live widget sizing reworked from a 6-step fixed preset search (real
  Carbonite's `MMScales`) to directly solving for the one square size
  that fills the window's shorter side at the current scale. The
  preset search caused visible bounce when zoomed in (every preset
  failing at once) and stepped jumps when resizing the window; the new
  math grows smoothly in lockstep with the background tiles.
  - Added a 10% fit margin (`FIT_MARGIN`) after the live widget was
    found to disappear entirely inside Orgrimmar and reappear outside
    it — an exact-fill target has zero slack for the position drift
    city sub-zones apparently introduce, so a small margin keeps it
    fitting instead of failing outright.
- Minimap's own zoom level is now kept in sync with the window's +/-
  zoom buttons (`ZoomController.lua`). Previously only the background
  world-art reacted to zoom; Blizzard's own rendered terrain has a
  separate, discrete zoom level that was never being touched.

### Right-click brightness menu (new: `MapContextMenu.lua`)
- Added a small right-click popup on the map window with a tile-map
  brightness slider, built on plain frame primitives rather than
  porting Carbonite's full menu system.
- Brightness range is 0–100% (plain alpha-style multiplier on the tile
  art's color channels) — an earlier 0–250% "overbrightening" version
  was tried and explicitly reverted.
- Closes on any click outside the menu, via an `OnUpdate` mouse-button
  poll rather than an invisible full-screen catcher frame — the
  catcher approach tripped Blizzard's protected-action taint warning
  by sitting on top of the action bars.
- Right-click again on the map toggles the menu closed (same action
  that opens it).

### Minimap icon dock (`MinimapDock.lua`)
- Fixed real addon/Blizzard minimap buttons being swept up as fake
  icons, or missed entirely:
  - The generic "anything anchored to Minimap" scan matched real
    Carbonite's own filter (exclude only `Model`-type objects) too
    loosely for this server — `MinimapBackdrop` (a decorative frame
    carrying the coordinate text) was getting grabbed and rendered as
    a stray sliver of tiny text in the bar. Narrowed to
    `IsObjectType("Button")` in both the one-time scan and the
    repeating child scan.
  - Blizzard's native minimap zoom buttons are real Button-type
    widgets anchored the same way a genuine addon launcher is; added
    to the name-exclude list.
  - A button whose width hadn't resolved yet was retried forever and
    never actually docked — real addon icons simply never appeared.
    Now falls back to Blizzard's standard 32px button size instead of
    waiting indefinitely.
- Added a mail icon to the dock. This server's client uses the modern
  (post-Shadowlands) minimap structure —
  `MinimapCluster.IndicatorFrame.MailFrame` — not the old flat
  `MiniMapMailFrame` global real Carbonite and this addon's own
  `KNOWN_NAMES` list both assumed. The dock forwards that real native
  button (keeping its working hover/tooltip) rather than building a
  fully standalone one:
  - The native button's own texture region is a numeric FileDataID
    that renders as nothing on this server; a separate, non-mouse-
    interactive overlay texture is layered on top instead so it can
    never block the hover.
  - Blizzard's `Interface\Minimap\MiniMap-MailIcon` art also does not
    exist on this client build at all (confirmed with an isolated
    on-screen test) — using `Interface\Icons\INV_Letter_15` instead
    (the same icon real Carbonite's own guide data uses for mailbox
    markers).
  - Visibility is driven by polling `HasNewMail()` every tick rather
    than trusting the native frame's own show/hide, matching real
    Carbonite's own `MailboxNotice` module, which doesn't trust it
    either.
  - Icon creation/acquisition is safe to retry every tick rather than
    once at startup — the native mail frame, like
    `GameTimeFrame`/`TimeManagerClockButton`, can be one of this
    server's lazily-created elements not yet present at addon load.

### Known open item
- A "large number of AddOn errors" popup was seen once with this
  menu open on screen; cause not yet confirmed. Deferred at the time —
  revisit with `/console scriptErrors 1` set and the exact error text
  next time it reproduces.
