"""Writes Quest/Data/QuestDBRules.lua: what the Carbonite rows don't carry.

Called by gen_quest_data.py, which owns the quest rows; everything here comes
from QuestieDB (see questie_db.py) and is keyed by the same quest and NPC ids.

    Rules       who can pick a quest up, and when: the quests that must be
                done first, the ones that rule it out, level, race,
                profession and reputation.
    StartItems  quests begun by an item that drops: the item, what drops it
                and where those are found.
    Patrols     the path a quest giver or turn-in NPC walks.
    QuestItems  items a quest hands you to use.
    ProvidedItems  items a quest asks for that no creature or object
                drops: crafted, bought, or brought.

QuestieDB is GPL-3.0, as is the Carbonite data this sits beside.
"""
from questie_db import _array

# Quest fields (QuestieDB/src/meta/questMeta.lua).
Q_STARTED_BY, Q_REQUIRED_LEVEL, Q_REQUIRED_RACES = 2, 4, 6
Q_OBJECTIVES, Q_SOURCE_ITEM, Q_PRE_GROUP, Q_PRE_SINGLE = 10, 11, 12, 13
Q_EXCLUSIVE_TO, Q_REQUIRED_SKILL, Q_MIN_REP, Q_MAX_REP = 16, 18, 19, 20
Q_REQUIRED_SOURCE_ITEMS, Q_NEXT_IN_CHAIN, Q_PARENT = 21, 22, 25
Q_BREADCRUMB_FOR, Q_REQUIRED_SPELL, Q_MAX_LEVEL = 27, 30, 32
NPC_SPAWNS, NPC_WAYPOINTS, OBJECT_SPAWNS = 7, 8, 4
ITEM_NPC_DROPS, ITEM_OBJECT_DROPS = 2, 3

# requiredRaces values that only say "this faction" - the row's own side field
# already does that. (QuestieDB/src/corrections/enum/expansions.lua.)
ALLIANCE_RACES = 1 + 4 + 8 + 64 + 4294967296
HORDE_RACES = 2 + 16 + 32 + 128 + 8589934592

START_ITEM_POINTS = 60      # most positions kept for one item-started quest
START_ITEM_CELL = 1.5       # ...after keeping one per cell this many zone-percent wide
WORLD_DROP_DROPPERS = 100  # an item dropped by more kinds of creature than this,
WORLD_DROP_ZONES = 6       # ...or in more zones than this, is a world drop: no map area
PATROL_STEP = 0.8           # patrol points closer than this (zone percent) are merged


def lua_str(text):
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


def ids(value):
    """A decoded id list (or a single id) -> [positive ints]."""
    if isinstance(value, int):
        value = [value]
    out = []
    for v in _array(value).values():
        if isinstance(v, int) and v > 0 and v not in out:
            out.append(v)
        elif isinstance(v, (list, dict)):       # preQuestGroup is sometimes nested
            for w in ids(v):
                if w not in out:
                    out.append(w)
    return out


def pair(value):
    """A decoded {id, amount} -> "id:amount" or None."""
    value = _array(value)
    a, b = value.get(1), value.get(2)
    if isinstance(a, int) and isinstance(b, (int, float)):
        return "%d:%d" % (a, b)
    return None


def coord(v):
    return ("%.1f" % v).rstrip("0").rstrip(".")


def quest_rule(questie, qid, side, min_level, quest_ids):
    get = lambda field: questie.value("Quest", qid, field)
    known = lambda field: [i for i in ids(get(field)) if i in quest_ids]
    parts = []

    single, group = known(Q_PRE_SINGLE), known(Q_PRE_GROUP)
    if single:
        parts.append("s=" + ",".join(map(str, single)))     # any one of these done
    elif group:
        parts.append("g=" + ",".join(map(str, group)))      # all of these done
    exclusive = [i for i in known(Q_EXCLUSIVE_TO) if i != qid]
    if exclusive:
        parts.append("x=" + ",".join(map(str, exclusive)))  # none of these done or taken
    for key, field in (("p", Q_PARENT), ("n", Q_NEXT_IN_CHAIN), ("b", Q_BREADCRUMB_FOR)):
        value = get(field)
        if isinstance(value, int) and value > 0 and value != qid and value in quest_ids:
            parts.append("%s=%d" % (key, value))

    level = get(Q_REQUIRED_LEVEL)
    if isinstance(level, int) and level > 0 and level != min_level:
        parts.append("l=%d" % level)
    max_level = get(Q_MAX_LEVEL)
    if isinstance(max_level, int) and max_level > 0:
        parts.append("L=%d" % max_level)

    races = get(Q_REQUIRED_RACES)
    if isinstance(races, int) and races > 0:
        faction_only = (races == ALLIANCE_RACES and side == 1) or (races == HORDE_RACES and side == 2)
        if not faction_only:
            parts.append("r=%d" % races)

    for key, field in (("k", Q_REQUIRED_SKILL), ("m", Q_MIN_REP), ("M", Q_MAX_REP)):
        packed = pair(get(field))
        if packed:
            parts.append("%s=%s" % (key, packed))
    spell = get(Q_REQUIRED_SPELL)
    if isinstance(spell, int) and spell != 0:
        parts.append("c=%d" % spell)     # negative: must NOT know it
    return ";".join(parts)


def map_points(questie, entity, ident):
    """{uiMapId: [(x, y)]} for an NPC or object, outdoor zones only."""
    out = {}
    spawns = questie.value(entity, ident, NPC_SPAWNS if entity == "Npc" else OBJECT_SPAWNS)
    if not isinstance(spawns, dict):
        return out
    for area, points in spawns.items():
        if not isinstance(area, int) or questie.dungeon_of(area):
            continue
        ui_map = questie.ui_map(area)
        if not ui_map:
            continue
        for p in _array(points).values():
            p = _array(p)
            x, y = p.get(1), p.get(2)
            if isinstance(x, (int, float)) and isinstance(y, (int, float)) and x > 0 and y > 0:
                out.setdefault(ui_map, []).append((x, y))
    return out


def thin(by_map, cell, cap):
    """One point per cell, then an even sample down to cap. Keeps map order."""
    kept = []
    for ui_map in sorted(by_map):
        seen = set()
        for x, y in by_map[ui_map]:
            key = (int(x / cell), int(y / cell))
            if key not in seen:
                seen.add(key)
                kept.append((ui_map, x, y))
    if len(kept) > cap:
        step = len(kept) / cap
        kept = [kept[int(i * step)] for i in range(cap)]
    out = {}
    for ui_map, x, y in kept:
        out.setdefault(ui_map, []).append((x, y))
    return out


def pack_points(by_map):
    return "|".join(
        "%d:%s" % (ui_map, ";".join("%s,%s" % (coord(x), coord(y)) for x, y in points))
        for ui_map, points in sorted(by_map.items()))


def start_item(questie, qid):
    """Packed StartItems value for a quest only an item starts, else None."""
    groups = _array(questie.value("Quest", qid, Q_STARTED_BY))
    if ids(groups.get(1)) or ids(groups.get(2)):
        return None
    items = ids(groups.get(3))
    if not items:
        return None
    item = items[0]
    name = questie.name("Item", item)
    if not name:
        return None
    droppers, by_map = [], {}
    for entity, field in (("Npc", ITEM_NPC_DROPS), ("Object", ITEM_OBJECT_DROPS)):
        for ident in ids(questie.value("Item", item, field)):
            who = questie.name(entity, ident)
            if who and who not in droppers:
                droppers.append(who)
            for ui_map, points in map_points(questie, entity, ident).items():
                by_map.setdefault(ui_map, []).extend(points)
    if len(droppers) > WORLD_DROP_DROPPERS or len(by_map) > WORLD_DROP_ZONES:
        # Drops anywhere (Pendant of Myzrael: 287 kinds of creature in 10
        # zones). Shading all of that only paints the map at random.
        return "%d|%s|world drop|" % (item, name)
    shown = ", ".join(droppers[:3]) + (" +%d more" % (len(droppers) - 3) if len(droppers) > 3 else "")
    return "|".join(filter(None, [
        "%d|%s|%s" % (item, name, shown),
        pack_points(thin(by_map, START_ITEM_CELL, START_ITEM_POINTS))]))


def patrol(questie, npc):
    """Packed Patrols value for an NPC that walks a path, else None."""
    waypoints = questie.value("Npc", npc, NPC_WAYPOINTS)
    if not isinstance(waypoints, dict):
        return None
    paths = []
    for area in sorted(k for k in waypoints if isinstance(k, int)):
        ui_map = questie.ui_map(area)
        if not ui_map or questie.dungeon_of(area):
            continue
        for path in _array(waypoints[area]).values():
            points = []
            for p in _array(path).values():
                p = _array(p)
                x, y = p.get(1), p.get(2)
                if not (isinstance(x, (int, float)) and isinstance(y, (int, float))):
                    continue
                if points and abs(points[-1][0] - x) < PATROL_STEP and abs(points[-1][1] - y) < PATROL_STEP:
                    continue
                points.append((x, y))
            # A path that never leaves one spot isn't worth a line.
            if len(points) >= 3:
                xs, ys = [p[0] for p in points], [p[1] for p in points]
                if max(xs) - min(xs) + max(ys) - min(ys) >= 2:
                    paths.append("%d:%s" % (ui_map, ";".join(
                        "%s,%s" % (coord(x), coord(y)) for x, y in points)))
    return "|".join(paths) or None


def quest_items(questie, qid):
    found = []
    source = questie.value("Quest", qid, Q_SOURCE_ITEM)
    for i in ids(source) + ids(questie.value("Quest", qid, Q_REQUIRED_SOURCE_ITEMS)):
        if i not in found:
            found.append(i)
    for entry in _array(_array(questie.value("Quest", qid, Q_OBJECTIVES)).get(3)).values():
        i = _array(entry).get(1)
        if isinstance(i, int) and i > 0 and i not in found:
            found.append(i)
    return found


ITEM_ITEM_DROPS, ITEM_QUEST_REWARDS, ITEM_LEVEL = 4, 6, 9
ITEM_CLASS, ITEM_SUBCLASS, ITEM_VENDORS = 12, 13, 14
CLASS_QUEST, CLASS_MISC = 12, 15


def provided_items(questie, qid):
    """2026-11-18 (user: Gizmo for Warug's Advanced Target Dummy, I Need a
    Tailor's White Bandit Mask - "highlight those items as player provided
    not a drop", and don't send me back to the giver without them).

    The items a quest asks for that aren't found in the world: not quest
    items, nothing drops or holds them, no quest rewards them - so they are
    crafted, bought or brought. Class 15 (tokens, mounts) is left out: those
    come from somewhere QuestieDB doesn't record, not from a profession.
    -> ["itemId:v:name" (v = 1 when a vendor sells it, else 0), ...]"""
    out = []
    for entry in _array(_array(questie.value("Quest", qid, Q_OBJECTIVES)).get(3)).values():
        item = _array(entry).get(1)
        if not isinstance(item, int) or item <= 0:
            continue
        sc = questie.scalars("Item", item)
        cls = sc.get(ITEM_CLASS)
        if cls in (CLASS_QUEST, CLASS_MISC):
            continue
        # Item level 1 "other" consumables are quest things put together
        # or handed out (Pamela's Doll, Craftsman's Writs), not crafts.
        if cls in (None, 0) and sc.get(ITEM_SUBCLASS) == 8 and (sc.get(ITEM_LEVEL) or 0) <= 1:
            continue
        if (ids(questie.value("Item", item, ITEM_NPC_DROPS)) or ids(questie.value("Item", item, ITEM_OBJECT_DROPS))
                or ids(questie.value("Item", item, ITEM_ITEM_DROPS))
                or ids(questie.value("Item", item, ITEM_QUEST_REWARDS))):
            continue
        name = questie.name("Item", item).replace(":", "").replace(",", "")
        if name:
            vendor = 1 if ids(questie.value("Item", item, ITEM_VENDORS)) else 0
            out.append("%d:%d:%s" % (item, vendor, name))
    return out


def write_rules(questie, path, header, quests, giver_names):
    """quests: {quest id: (side, min level)}; giver_names: {giver id: name}."""
    quest_ids = set(quests)
    rules, start_items, items, provided = [], [], [], []
    for qid in sorted(quests):
        side, min_level = quests[qid]
        rule = quest_rule(questie, qid, side, min_level, quest_ids)
        if not questie.name("Quest", qid):
            rule = "?"      # QuestieDB has no record of it: fall back to QuestPrev
        if rule:
            rules.append((qid, lua_str(rule)))
        packed = start_item(questie, qid)
        if packed:
            start_items.append((qid, lua_str(packed)))
        found = quest_items(questie, qid)
        if found:
            items.append((qid, lua_str(",".join(map(str, found)))))
        mine = provided_items(questie, qid)
        if mine:
            provided.append((qid, lua_str(",".join(mine))))

    patrols = []
    for npc in sorted(giver_names):
        # Giver ids are NPC, object or item ids; only take a path when
        # QuestieDB's NPC of that id is the same one by name.
        if questie.name("Npc", npc).lower() != giver_names[npc].lower():
            continue
        packed = patrol(questie, npc)
        if packed:
            patrols.append((npc, lua_str(packed)))

    def block(name, comment, rows, per_line=1):
        out = [""] + ["-- " + line for line in comment] + ["QuestData.%s = {" % name]
        for n in range(0, len(rows), per_line):
            out.append("".join("[%d]=%s," % row for row in rows[n:n + per_line]))
        out.append("}")
        return out

    lines = [header,
             "local AzerothAtlas = _G.AzerothAtlas",
             "AzerothAtlas.QuestData = AzerothAtlas.QuestData or {}",
             "local QuestData = AzerothAtlas.QuestData"]
    lines += block("Rules", [
        "Quest id -> \"key=value;...\": what has to be true before the quest is",
        "offered. Quest lists are comma-separated ids.",
        "  s  any one of these quests turned in     g  all of these turned in",
        "  x  none of these turned in or in the log (mutually exclusive quests)",
        "  p  this quest in the log (a sub-quest of it)",
        "  n  not once this follow-up is turned in or in the log",
        "  b  a breadcrumb: not once the quest it leads to is turned in or taken",
        "  l  minimum level, where it differs from the row's own   L  maximum level",
        "  r  race bit mask (1 Human, 2 Orc, 4 Dwarf, 8 Night Elf, 16 Undead,",
        "     32 Tauren, 64 Gnome, 128 Troll, ...), where narrower than a faction",
        "  k  skillLineId:rank    m / M  factionId:standing at least / at most",
        "  c  a spell that must be known (negative: must not be)",
        "\"?\" marks a quest QuestieDB has no record of.",
    ], rules, 4)
    lines += block("StartItems", [
        "Quest id -> \"itemId|item name|what drops it|mapId:x,y;x,y|mapId:...\" for a",
        "quest begun by an item rather than a person. Positions are where the",
        "things that drop it are found (zone percent), thinned to a sample.",
    ], start_items)
    lines += block("Patrols", [
        "Quest giver / turn-in NPC id -> \"mapId:x,y;x,y;...|mapId:...\": the paths",
        "it walks (zone percent), for NPCs that don't stand still.",
    ], patrols)
    lines += block("QuestItems", [
        "Quest id -> item ids the quest gives or asks you to carry. The tracker",
        "offers a button for the ones that can be used.",
    ], items, 6)
    lines += block("ProvidedItems", [
        "Quest id -> \"itemId:vendor:name,...\": items the quest asks for that",
        "nothing in the world drops or holds - crafted, bought or brought by the",
        "player (vendor 1: a vendor sells it). Shown as such on the tracker and",
        "list, and routing doesn't send you to the turn-in until you have them.",
    ], provided)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return len(rules), len(start_items), len(patrols), len(items)
