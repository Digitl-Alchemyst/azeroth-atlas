"""Quests QuestieDB knows that Carbonite.Quests doesn't, as catalog rows.

Carbonite's data stops at what Carbonite shipped; this server adds hundreds of
quests of its own (ids from 90000 up, in zones like The Drowned City) and runs
others Carbonite never had. QuestieDB's Forever database has them, so for every
quest id it has and the Carbonite rows lack, this writes a row in Carbonite's
own shape - header, giver, turn-in, objective spawn points - which the catalog
then loads like any other (Quest/Data/QuestDBImported.lua).

Also evaluates Questie's quest blacklist (Questie/Database/Corrections/
QuestieQuestBlacklist.lua) for this server: quests that are duplicates, not in
the game, or only make sense in another expansion. Questie decides that list
at runtime from the client's expansion; this server reports itself as the
original game (Expansions.Current = Era, Questie's own Forever rule), so the
conditions are worked out here once. The result is a list of quest ids kept
off the map, Carbonite's rows included.

Positions are QuestieDB spawns: an NPC or object giver at each place it stands
(the first as the row's Start, the rest as alternates); an objective at the
spawns of the creatures to kill, objects to use, and the creatures / objects
an item drops from. Objective order follows QuestieDB (creatures, objects,
items, then credit and exploration objectives), which is the order the game
lists them in for nearly every quest.
"""

import re

from questie_db import _array
from gen_quest_rules import ids, map_points, thin, coord, lua_str, ALLIANCE_RACES, HORDE_RACES

Q_NAME, Q_STARTED_BY, Q_FINISHED_BY = 1, 2, 3
Q_REQUIRED_LEVEL, Q_QUEST_LEVEL, Q_REQUIRED_RACES = 4, 5, 6
Q_TRIGGER_END, Q_OBJECTIVES, Q_NEXT_IN_CHAIN, Q_ZONE_OR_SORT = 9, 10, 22, 17
ITEM_NPC_DROPS, ITEM_OBJECT_DROPS = 2, 3

GIVER_SPAWNS = 8            # giver / turn-in positions kept per quest (first + alternates)
OBJECTIVE_POINTS = 40       # spawn points kept per objective...
OBJECTIVE_CELL = 1.0        # ...one per cell this many zone-percent wide

# Names QuestieDB uses for placeholder and retired quests.
JUNK_NAME = re.compile(r"<\s*(NYI|TXT|UNUSED|CHANGE|DEPRECATED|TEST)|\[DEPRECATED\]|^zz|^\[?test\b", re.I)

# Quest sorts (negative zoneOrSort) for holidays. Their rows get category
# HOLIDAY_CATEGORY, one of the Carbonite category numbers QuestCatalog.lua's
# HOLIDAY_CATEGORY treats as an event quest - shown only with "Map: show
# holiday/event quests" on.
HOLIDAY_SORTS = {-22, -41, -364, -366, -369, -370, -374, -375, -376, -1001, -1002, -1003, -1005, -1006}
HOLIDAY_CATEGORY = 3

BLACKLIST_ENTRY = re.compile(r"^\s*\[(\d+)\]\s*=\s*(.+?),\s*(?:--.*)?$")
EXPANSIONS = {"Era": 1, "Tbc": 2, "Wotlk": 3, "Cata": 4, "MoP": 5}


def _eval_blacklist(expr):
    """True to hide, False to keep, None when the condition can't be read."""
    expr = expr.strip()
    if expr in ("true", "HIDE_ON_MAP"):
        return True
    if expr == "false":
        return False
    py = expr
    py = re.sub(r"Expansions\.Current", "1", py)
    py = re.sub(r"Expansions\.(\w+)", lambda m: str(EXPANSIONS.get(m.group(1), "X")), py)
    py = py.replace("HIDE_ON_MAP", "True").replace("~=", "!=")
    py = re.sub(r"not\s+Questie\.Is\w+", "True", py)
    py = re.sub(r"Questie\.Is\w+", "False", py)
    py = re.sub(r"\btrue\b", "True", py)
    py = re.sub(r"\bfalse\b", "False", py)
    if not re.fullmatch(r"[\d\s<>=!()TrueFalsandot]+", py):
        return None
    try:
        return bool(eval(py, {"__builtins__": {}}, {}))
    except Exception:
        return None


def read_blacklist(path):
    """Quest ids Questie keeps off the map on this server."""
    text = path.read_text(encoding="utf-8")
    body = text[text.index("local questsToBlacklist = {"):]
    body = body[:body.index("\n    }\n")]
    hidden, unread = set(), 0
    for line in body.splitlines():
        m = BLACKLIST_ENTRY.match(line)
        if not m:
            continue
        verdict = _eval_blacklist(m.group(2))
        if verdict is None:
            unread += 1
        elif verdict:
            hidden.add(int(m.group(1)))
    return hidden, unread


HOLIDAY_ENTRY = re.compile(r"eventQuests,\s*\{\s*\"[^\"]*\",\s*(\d+)")


def read_holidays(folder):
    """Quest ids of holiday quests (Questie/Database/Corrections/Holidays/quests).

    Questie blacklists many of these and lets them back in while their holiday
    runs; here the "show holiday/event quests" option does that job instead, so
    they must not end up blacklisted for good."""
    found = set()
    for path in sorted(folder.glob("*.lua")):
        found.update(int(m.group(1)) for m in HOLIDAY_ENTRY.finditer(path.read_text(encoding="utf-8")))
    return found


def _side(races):
    if not isinstance(races, int) or races <= 0:
        return ""
    alliance, horde = races & ALLIANCE_RACES, races & HORDE_RACES
    if alliance and not horde:
        return "1"
    if horde and not alliance:
        return "2"
    return ""


def _clean(text):
    return re.sub(r"[|;\"\]\[]", "", text or "").strip()


def _givers(questie, value, names):
    """Packed giver strings for a startedBy / finishedBy value."""
    groups = _array(value)
    out = []
    for group, entity in ((1, "Npc"), (2, "Object")):
        for ident in ids(groups.get(group)):
            name = questie.name(entity, ident)
            if not name:
                continue
            spawns = thin(map_points(questie, entity, ident), 2.0, GIVER_SPAWNS)
            for ui_map, points in sorted(spawns.items()):
                for x, y in points:
                    if entity == "Npc":
                        names.setdefault(ident, name)
                        head = str(ident)
                    else:
                        head = _clean(name)     # objects go by name: their ids aren't NPC ids
                    out.append("%s|%d|32|%s|%s" % (head, ui_map, coord(x), coord(y)))
    return out[:GIVER_SPAWNS]


def _objectives(questie, qid):
    """[(label, {uiMap: [(x, y)]})] in QuestieDB objective order."""
    out = []
    objs = _array(questie.value("Quest", qid, Q_OBJECTIVES))

    def add(label, by_map):
        out.append((_clean(label), thin(by_map, OBJECTIVE_CELL, OBJECTIVE_POINTS)))

    for entry in _array(objs.get(1)).values():          # creatures to kill
        npc = _array(entry).get(1)
        if isinstance(npc, int):
            add(questie.name("Npc", npc) or "", map_points(questie, "Npc", npc))
    for entry in _array(objs.get(2)).values():          # objects to use
        obj = _array(entry).get(1)
        if isinstance(obj, int):
            add(questie.name("Object", obj) or "", map_points(questie, "Object", obj))
    for entry in _array(objs.get(3)).values():          # items to collect
        item = _array(entry).get(1)
        if not isinstance(item, int):
            continue
        by_map = {}
        for entity, field in (("Npc", ITEM_NPC_DROPS), ("Object", ITEM_OBJECT_DROPS)):
            for ident in ids(questie.value("Item", item, field)):
                for ui_map, points in map_points(questie, entity, ident).items():
                    by_map.setdefault(ui_map, []).extend(points)
        add(questie.name("Item", item) or "", by_map)
    for entry in _array(objs.get(5)).values():          # kill credit: any of several creatures
        entry = _array(entry)
        by_map = {}
        for npc in ids(entry.get(1)):
            for ui_map, points in map_points(questie, "Npc", npc).items():
                by_map.setdefault(ui_map, []).extend(points)
        label = entry.get(3) if isinstance(entry.get(3), str) else ""
        add(label, by_map)

    trigger = _array(questie.value("Quest", qid, Q_TRIGGER_END))   # "explore this place"
    spots = trigger.get(2)
    if isinstance(spots, dict):
        by_map = {}
        for area, points in spots.items():
            ui_map = isinstance(area, int) and questie.ui_map(area)
            if not ui_map:
                continue
            for p in _array(points).values():
                p = _array(p)
                x, y = p.get(1), p.get(2)
                if isinstance(x, (int, float)) and isinstance(y, (int, float)) and x > 0 and y > 0:
                    by_map.setdefault(ui_map, []).append((x, y))
        label = trigger.get(1) if isinstance(trigger.get(1), str) else ""
        add(label, by_map)
    return out


def import_rows(questie, known_ids, blacklist, holidays=frozenset()):
    """{quest id: row source}, {npc id: name}, start alts, end alts, headers, counts."""
    rows, names, start_alts, end_alts, headers = {}, {}, [], [], {}
    counts = {"imported": 0, "with giver": 0, "no giver": 0, "skipped": 0}
    for qid in questie.quest_ids():
        if qid in known_ids:
            continue
        name = questie.name("Quest", qid)
        if not name or JUNK_NAME.search(name) or qid in blacklist:
            counts["skipped"] += 1
            continue
        get = lambda field: questie.value("Quest", qid, field)
        side = _side(get(Q_REQUIRED_RACES))
        min_level = get(Q_REQUIRED_LEVEL)
        min_level = min_level if isinstance(min_level, int) and min_level > 0 else 1
        level = get(Q_QUEST_LEVEL)
        level = level if isinstance(level, int) and level > 0 else min_level
        nxt = get(Q_NEXT_IN_CHAIN)
        nxt = nxt if isinstance(nxt, int) and nxt > 0 else 0
        sort = get(Q_ZONE_OR_SORT)
        category = HOLIDAY_CATEGORY if (sort in HOLIDAY_SORTS or qid in holidays) else 0

        parts = ["Quest=[=[%s|%s|%d|%d|%d|%d|0]=]" % (_clean(name), side, level, min_level, nxt, category)]
        starts = _givers(questie, get(Q_STARTED_BY), names)
        ends = _givers(questie, get(Q_FINISHED_BY), names)
        if starts:
            parts.append("Start=%s" % lua_str(starts[0]))
            if len(starts) > 1:
                start_alts.append((qid, lua_str(";".join(starts))))
        if ends:
            parts.append("End=%s" % lua_str(ends[0]))
            if len(ends) > 1:
                end_alts.append((qid, lua_str(";".join(ends))))
        objectives = []
        for n, (label, by_map) in enumerate(_objectives(questie, qid), 1):
            points = ["%s|%d|32|%s|%s" % (label, ui_map, coord(x), coord(y))
                      for ui_map, pts in sorted(by_map.items()) for x, y in pts]
            if points:
                objectives.append("[%d]={%s}" % (n, ",".join(lua_str(p) for p in points)))
        if objectives:
            parts.append("Objectives={%s}" % ",".join(objectives))

        rows[qid] = "{%s}" % ",".join(parts)
        headers[qid] = (int(side or 0), min_level)
        counts["imported"] += 1
        counts["with giver" if starts else "no giver"] += 1
    return rows, names, start_alts, end_alts, headers, counts


def write_import(questie, path, header, rows, names, start_alts, end_alts, blacklist):
    def block(name, items, per_line=1):
        out = []
        for n in range(0, len(items), per_line):
            out.append("".join("%s[%d]=%s;" % (name, i, v) for i, v in items[n:n + per_line]))
        return out

    hidden = sorted(blacklist)
    lines = [header,
             "local AlchemyGPS = _G.AlchemyGPS",
             "AlchemyGPS.QuestData = AlchemyGPS.QuestData or {}",
             "local QuestData = AlchemyGPS.QuestData",
             "",
             "-- Quest rows in Carbonite's shape, for quests the Carbonite data lacks.",
             "-- A builder like QuestDB1-6's, run by QuestCatalog.lua after login.",
             "QuestData.Chunks = QuestData.Chunks or {}",
             "QuestData.Chunks[#QuestData.Chunks + 1] = function()",
             "return {"]
    lines += ["[%d]=%s," % (qid, rows[qid]) for qid in sorted(rows)]
    lines += ["}", "end", "",
              "-- Giver / turn-in NPC names for the rows above, added to the",
              "-- Carbonite names table (QuestDBExtras.lua, loaded before this file).",
              "local Names = QuestData.Names or {}",
              "QuestData.Names = Names"]
    lines += block("Names", [(i, lua_str(n)) for i, n in sorted(names.items())], per_line=4)
    lines += ["", "-- Other places the rows' givers / turn-ins stand.",
              "local StartAlts = QuestData.StartAlts or {}",
              "QuestData.StartAlts = StartAlts"]
    lines += block("StartAlts", start_alts)
    lines += ["local EndAlts = QuestData.EndAlts or {}",
              "QuestData.EndAlts = EndAlts"]
    lines += block("EndAlts", end_alts)
    lines += ["", "-- Questie's quest blacklist as it applies on this server: duplicates,",
              "-- quests not in the game, quests for another expansion. Never offered",
              "-- on the map.",
              'QuestData.Blacklist = "%s"' % ",".join(map(str, hidden))]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
