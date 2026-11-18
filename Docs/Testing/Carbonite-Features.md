# Alchemy GPS — Carbonite Features Test Plan

Nov 18, 2026 · @Digital Alchemyst

## Before you start

This plan covers every Carbonite feature added on Nov 18: the ✅ rows (and checks that the parked 1.27 stays off) in `Docs/Compare-Carbonite.md`. Section numbers match that doc. None of it has been tested in game yet, and none of it is committed.

- **Restart the game fully once** before testing; `/reload` won't load the new files. After that, `/reload` is enough between fixes. The new files are `GuideTrainer.lua`, `AreaLabels.lua`, `Travel.lua`, `Waypoints.lua`, `MouseActions.lua`, `CombatState.lua`, `AddonPins.lua`, `GatherRecorder.lua`, `QuestDetails.lua`, `QuestNotify.lua`, `QuestTooltips.lua`, the new TGA images and `Snd\QuestComplete.ogg`.
- **Show Lua errors**: type `/console scriptErrors 1`, or use BugSack. Any red error box counts as a fail for the step you were on.
- **You'll need**: a capital city, a flight master (open its map once), a herbalism or mining character, a quest log with a few quests (at least one in a chain), and for some steps a group member or friend who also runs Alchemy GPS.
- **Where settings are**: `/gps settings`, then the **Map** or **Quests** tab. The names in bold below are the headings and checkboxes in those tabs.
- **Recording results**: set each step's Result to Pass, Fail or Not tested. For a fail, add a comment saying what you saw, with a screenshot if you can.
- **Quest problems**: type `/gps quest dump <questID>` and paste the lines into your comment.

# Part 1 — Map

## 1.2 Trainer icons

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.2.1 | Open the map's Filters menu | **Class Trainers** and **Profession Trainers** rows are there. |  |
| 1.2.2 | Open your capital city | Trainer icons show. Hovering one says what it is (e.g. "Mining Trainer"). |  |
| 1.2.3 | Look at the class trainers | Only **your own class's** trainers show, and only your faction's. |  |
| 1.2.4 | Untick each row in turn | Only that kind of trainer disappears. |  |

## 1.4 Subzone names

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.4.1 | Zoom the map in on Elwynn Forest | Names like **Goldshire** and **Northshire Valley** fade in. Zooming out fades them out. |  |
| 1.4.2 | Settings > Map > Map layers: untick **Subzone names (Goldshire...) as you zoom in** | The names go away. Tick it again and they're back. |  |

## 1.6 Travel routes with flight paths

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.6.1 | Open a flight master's taxi map once | This is how the addon learns your flight points. Nothing visible happens. |  |
| 1.6.2 | Set a goto in a far zone on the same continent | The arrow and ant trail lead to a **flight master** first, not straight across the map. |  |
| 1.6.3 | Set a goto across the sea | The route goes through the right **boat, zeppelin or portal**. |  |
| 1.6.4 | Set a goto a short walk away | It walks straight there, with no flight detour. |  |
| 1.6.5 | Settings > Map > Navigation: untick **Travel routes: use flight paths, boats and portals** | The arrow points straight at the target again. |  |

## 1.8 Follow your flight

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.8.1 | Take a flight | While flying, the arrow points to **where the flight lands** and counts down. |  |
| 1.8.2 | Land | The arrow goes back to your goto or quest. |  |
| 1.8.3 | Take the same flight again | The time estimate is closer to the real time (it remembers flight times). |  |
| 1.8.4 | Untick **Follow your flight: the arrow points where it lands**, then fly | The arrow isn't changed during the flight. |  |

## 1.9 TomTom emulation (`/way`)

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.9.1 | Type `/way 50 50 Test` | A waypoint pin appears in the middle of your zone, and the arrow points to it. |  |
| 1.9.2 | Type `/way Elwynn Forest 42 65 Goldshire` | A waypoint is set in that zone. |  |
| 1.9.3 | `/way list`, then `/cway`, then `/wayb` | It lists the waypoints, points the arrow at the closest, then adds one where you stand. |  |
| 1.9.4 | Walk onto a waypoint | It clears, and the arrow moves to the closest one left. |  |
| 1.9.5 | `/way reset all` | Every waypoint clears. |  |
| 1.9.6 | With Questie (or another addon that uses TomTom), use its "set waypoint" option | The waypoint lands on **our** map and arrow. |  |
| 1.9.7 | Untick **Act as TomTom**, then `/reload` | `/way` is no longer ours. `/gps way` still works. |  |
| 1.9.8 | Enable the real TomTom addon | No errors. TomTom keeps its own arrow and ours stays out of the way. |  |

## 1.10 Track a player

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.10.1 | In a group, right-click a party member's dot | The menu shows **Track with the arrow** and **Whisper**, plus **Invite** for guildmates and friends. |  |
| 1.10.2 | Choose **Track with the arrow** | The arrow points at them, a light-blue trail leads to them, and their dot is bigger. |  |
| 1.10.3 | Right-click the arrow (or the dot) > **Stop tracking** | Tracking stops. |  |
| 1.10.4 | Track someone, then have them leave the group | Tracking stops on its own, with a chat message. |  |
| 1.10.5 | In a battleground, right-click a dot | **Report AFK** is offered. |  |

## 1.11 Arrow extras

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.11.1 | Settings > Quests > Arrow: tick **Show how many degrees you're off course** | A text line under the arrow shows the degrees. |  |
| 1.11.2 | Tick **Click the arrow to target who you're heading to**, head to a quest NPC, click the arrow | That NPC is targeted. Try both in and out of combat. |  |
| 1.11.3 | Tick **Hide the arrow in battlegrounds**, enter one | The arrow is hidden. |  |
| 1.11.4 | Move the **Arrow size**, **Arrow X offset** and **Arrow Y offset** sliders | The arrow changes live. After `/reload` it stays put. |  |
| 1.11.5 | Drag the arrow | The X and Y sliders follow. |  |

## 1.12 Mouse clicks on the map

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.12.1 | Settings > Map > Mouse clicks on the map | Every click type says **Nothing**. Clicking one lists the jobs it can do. |  |
| 1.12.2 | Set **Ctrl + left click** to **Set the goto here**, then Ctrl-click the map | A goto is set there. |  |
| 1.12.3 | Try **Add a waypoint here**, **Zoom in**, **Switch small / big map**, **Open the quest list** on other clicks | Each does its job. |  |
| 1.12.4 | Try middle-click and buttons 4 / 5 (if your mouse has them) | They work too. |  |
| 1.12.5 | Plain left drag and plain right-click | Still drag the map and open the right-click menu. |  |

## 1.14 In combat

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.14.1 | Open the big map, then pull a mob | The map drops to the small map. |  |
| 1.14.2 | Open the quest list, then pull a mob | The list closes. |  |
| 1.14.3 | Finish the fight | Both come back as they were. |  |
| 1.14.4 | Untick each checkbox under **In combat** in turn | That part stops happening. |  |
| 1.14.5 | Resize the map during combat | It resizes, with no "blocked action" error. |  |

## 1.15 Movement trail

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.15.1 | Settings > Map > Movement trail: tick **Show a trail of dots where you've walked**, walk around | A red-orange dot trail follows you. |  |
| 1.15.2 | Move **Yards between dots**, **Most dots**, **Seconds a dot lasts** | Each changes the trail. |  |
| 1.15.3 | Stand still for longer than the dot time | Old dots disappear. |  |

## 1.19 Other addons' pins on the big map

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.19.1 | Enable Questie, HandyNotes or GatherMate2, open the big map (M) | Their icons show on our map. |  |
| 1.19.2 | Untick **Other addons' pins (big map)** in Filters | They go away. |  |
| 1.19.3 | Open Blizzard's map (Alt+M) | Those icons still show and work there. |  |

## 1.21 Brightness and opacity by layer

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.21.1 | Right-click the map | **Set goto here**, **Add a waypoint here**, **Clear goto** on top, then two columns, **Map layers** and **Icons**. Each slider shows its %. |  |
| 1.21.2 | Move **Zone art**, **Terrain**, **Quest areas** | Each changes its layer live. |  |
| 1.21.3 | Open Stormwind and move **City maps** | The city art gets darker or brighter. |  |
| 1.21.4 | Open a dungeon from the Dungeons menu and move **Dungeon maps** | The dungeon art gets darker or brighter. |  |
| 1.21.5 | Move **Unexplored areas** in a zone you haven't fully explored | 0% is black, 100% looks explored. |  |
| 1.21.6 | Move **Map icons**, **Quest icons**, **Gathering icons**, **Gathering icon size**, **Gathering backdrop** | Each changes its icons live. |  |
| 1.21.7 | Settings > Map > **Brightness and opacity** | The same 11 sliders. A change on one side shows on the other. |  |
| 1.21.8 | Right-click near the **bottom** of the screen | The menu opens **upward**. |  |
| 1.21.9 | Right-click near the **right edge** | The menu opens to the **left**. It never runs off the screen. |  |
| 1.21.10 | Open small pop-up menus near the bottom (a dot's menu, the Dungeons list, a Settings dropdown) | They open upward too. |  |
| 1.21.11 | `/reload` | Every slider keeps its value. |  |

## 1.25 Record the nodes you gather

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.25.1 | Gather a herb or mine a vein | An icon appears there at once. Its tooltip says **You gathered here**. |  |
| 1.25.2 | Gather the same node again later | No second icon. |  |
| 1.25.3 | Open a treasure chest, then a door or quest object | The chest is recorded, the door or object isn't. |  |
| 1.25.4 | Log in on another character | Your recorded nodes show there too. |  |
| 1.25.5 | Settings > Map > Gathered nodes: click **Clear herb (N)** | Only your recorded herbs go. The built-in nodes stay. Mining and treasure work the same way. |  |
| 1.25.6 | Untick **Record the herbs, ore and treasure you gather**, gather something | It isn't recorded. |  |

## 1.26 Import from GatherMate2_Data

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.26.1 | With GatherMate2 off, click **Import from GatherMate2_Data** | A message says to enable GatherMate2 and GatherMate2_Data first. No error. |  |
| 1.26.2 | Enable both, `/reload`, click Import | A message gives herb, mining and treasure counts. The status line says "Using imported data (date)". |  |
| 1.26.3 | Disable GatherMate2 again, `/reload` | The nodes still show, and there's no GatherMate2 popup. |  |
| 1.26.4 | Click **Remove import** | The status says "Using the map's built-in gathering data". |  |

## 1.27 Node glow — parked

Switched off on Nov 18 because every possible node spot glowed, not just the nodes that are actually up. Its settings are hidden until it's revisited ([issue #2](https://github.com/Digitl-Alchemyst/alchemy-gps/issues/2)).

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.27.1 | Look at gathering icons | **No** glow on any of them. |  |
| 1.27.2 | Settings > Map > Gathered nodes | No glow settings: just the record checkbox, the clear buttons and the import. |  |

## 1.28 Friends on the map

You need a friend on your friends list, not in your group, who also runs Alchemy GPS.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 1.28.1 | Both log in on the same continent | Their **yellow** dot shows within about 10–20 seconds. |  |
| 1.28.2 | Use a friend who's also in your guild | Their dot is **green**, not yellow. |  |
| 1.28.3 | Right-click their dot | Track, Whisper and Invite. |  |
| 1.28.4 | Untick **Friends (yellow)** in Settings > Map > Players | Their dot goes. |  |
| 1.28.5 | Untick **Share my position with online friends** | You stop showing on their map (it fades within a minute). |  |
| 1.28.6 | Go into a dungeon | Your position isn't sent. |  |

# Part 2 — Quests

## 2.3 Party tab

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.3.1 | In a group, open the quest list (L) and click **Party** | Each member gets a header, then their quests. The title reads "Quest List - Party". |  |
| 2.3.2 | Look at a member who runs Alchemy GPS | Their **whole** log shows. |  |
| 2.3.3 | Look at a member who doesn't | Only the quests you share show, with a note saying so. |  |
| 2.3.4 | Look at quests you both have | They say **you too**. Clicking one routes the arrow to it. |  |
| 2.3.5 | Click **Shared only**, then **Show all** | Shared only leaves just the quests you both have; Show all brings the rest back. |  |
| 2.3.6 | Leave the group | "You're not in a group." **My quests** goes back to the normal list. |  |

## 2.4 Search box

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.4.1 | Type part of a quest name | Only matches show. The top-right says "N of M match". |  |
| 2.4.2 | Type a zone name, then an objective word (e.g. "wolf") | Those match too. |  |
| 2.4.3 | Search while a zone is folded | Its matches show anyway. |  |
| 2.4.4 | Clear the box (or press Escape) | The full list is back. |  |
| 2.4.5 | Search in the Party view | It filters there too. |  |

## 2.5 Quest text beside the list

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.5.1 | Right-click a quest > **Show quest text** | A parchment panel opens beside the list (on the left if there's no room on the right). |  |
| 2.5.2 | Read it | Title, level and zone, Progress, Quest Objectives, Description, and who in your group has it. |  |
| 2.5.3 | Click another quest while it's open | The panel switches to it, and that row is highlighted. |  |
| 2.5.4 | Click the panel's X, then reopen it and close the quest list | Both close it. |  |
| 2.5.5 | Settings > Quests > Quest text: untick **Parchment background** | Dark background, white text. |  |
| 2.5.6 | Try each **Text colour** choice and the **Quest text size** slider | The panel changes live. |  |
| 2.5.7 | Untick **Show quest text in a panel beside the list** | The text opens under the quest again, as before. |  |

## 2.6 Quest IDs, chain parts, dailies

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.6.1 | Look at a chain quest in the list | **(part 2/4)** after its title. The tooltip says "Part 2 of 4 in a chain". |  |
| 2.6.2 | Tick **Show quest IDs** (Settings > Quests > Quest list) | "#1234" after each title. The tooltip always shows "Quest ID". |  |
| 2.6.3 | Open the quest text panel | Its second line shows "Part X of Y" and "ID …". |  |
| 2.6.4 | With a daily in your log (or one done today) | A blue line at the top says "Dailies: N done today, N in your log, reset in …". WoW Forever may have no dailies; if so, this never shows and that's fine. |  |

## 2.7 Links

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.7.1 | **Shift-right-click** a quest in the **list** | Chat opens with the quest link, then "(level 12, part 2/4)". |  |
| 2.7.2 | **Shift-right-click** a quest in the **tracker** | The same. |  |
| 2.7.3 | Open a chat box first, then shift-right-click | The link goes into the open box. |  |
| 2.7.4 | Send it and click the link | The game's quest tooltip opens. |  |
| 2.7.5 | Right-click a quest (list or tracker) > **Copy Wowhead link** | A box shows the link already selected. Ctrl+C copies it. |  |
| 2.7.6 | Untick **Quest links in chat say the level and chain part** | Just the link. |  |

## 2.11 Auto-watch, and the arrow staying on what you're doing

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.11.1 | Untrack a quest, then kill or loot something for it | It's tracked again. |  |
| 2.11.2 | Tick **Stop tracking a quest once it's ready to hand in**, finish a quest | It leaves the tracker. |  |
| 2.11.3 | With auto-track on and two quests nearby, make progress on quest A | The arrow **stays on A** and doesn't hop to B just because B is a bit closer. |  |
| 2.11.4 | Wait about 3 minutes without progress | It goes back to plain nearest-first. |  |

## 2.12 Progress messages to the group

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.12.1 | Check the setting first | **Tell my party / raid in chat as my objectives progress** is **off**. |  |
| 2.12.2 | Tick it, group up, kill a quest mob | Party chat says "Quest title: Kobold Vermin slain: 1/10". |  |
| 2.12.3 | Set **Say it every this many kills / items** to 5 | Messages only at 5/10 and 10/10, and when an objective finishes. |  |
| 2.12.4 | Finish the quest | "Quest title: ready to turn in". |  |
| 2.12.5 | Loot several quest items at once | Messages come about 1.5 s apart, not in a flood. |  |
| 2.12.6 | Progress while not in a group | Nothing is sent. |  |

## 2.13 Quest-complete sound

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.13.1 | Finish a quest's last objective | The chime plays. |  |
| 2.13.2 | Settings > Quests > Quest progress > **Sound**: pick each of the 8 | Each plays when picked. **Play** replays the chosen one. |  |
| 2.13.3 | Pick **A random one of these**, finish two quests | Different sounds. |  |
| 2.13.4 | Pick **No sound** | Silent. |  |
| 2.13.5 | Pick up a quest that's complete straight away ("go and talk to…") | No sound. |  |

## 2.15 Quest info on tooltips

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| 2.15.1 | Hover a mob a quest needs killed | The tooltip adds "Quest: [level] title" and its line, e.g. "Kobold Vermin slain: 4/10". |  |
| 2.15.2 | Hover a quest item in your bags | The same, with the item's line. |  |
| 2.15.3 | Hover the NPC who takes in one of your quests | **Hand in here:** in green when it's done, or "Hands in here (not done yet)". |  |
| 2.15.4 | Hover a mob the game already shows quest lines for | No quest appears twice. |  |
| 2.15.5 | Untick **Quest progress on mob and item tooltips** | No added lines. |  |
| 2.15.6 | Known limit: hover a mob that only **drops** a quest item | No line. Our data has no drop tables (Carbonite has the same limit). |  |

# Risks and regression checks

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| R.1 | Play normally for 30 minutes (questing, flying, gathering) | No Lua errors, no stutter. |  |
| R.2 | Open Blizzard's map (Alt+M) and the game's own quest log | Both work as before. |  |
| R.3 | `/reload` with the big map, quest list and quest text panel open | Everything comes back without errors. |  |
| R.4 | Check the arrow's order of priority: corpse run → flight → tracked player → goto/waypoint → quest | The arrow always follows the highest one active. |  |
