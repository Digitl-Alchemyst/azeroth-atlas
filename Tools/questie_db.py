"""Read-only access to QuestieDB's stored data, for gen_quest_data.py.

The "Forever" flavor of QuestieDB keeps every quest, NPC, object and item in
its .toc as metadata lines:

    ## X-Quest-2342-S:  <base64 CBOR>   scalar fields, keyed by field index
    ## X-Quest-2342-10: <base64 CBOR>   one table field (10 = objectives)
    ## X-Quest-IDS:     ~18~            a value split over -1 .. -18 parts

(QuestieDB/src/read/baked.lua is the addon's own reader.) Field indices come
from QuestieDB/src/meta/*Meta.lua. Only what the dungeon lookup needs is
decoded here: where a quest's objectives, givers and turn-ins are found, and
which of QuestieDB's area ids are dungeons.

QuestieDB is GPL-3.0, like the Carbonite quest data the addon is built from
(itself largely a Questie export). gen_quest_data.py asks it "which dungeon is
this in?"; gen_quest_rules.py takes prerequisites, patrol paths and the drop
locations of quest-starting items from it.
"""
import base64
import re
import struct
from pathlib import Path

# Field indices (QuestieDB/src/meta/{quest,npc,object,item}Meta.lua).
QUEST_STARTED_BY, QUEST_FINISHED_BY = 2, 3
QUEST_TRIGGER_END, QUEST_OBJECTIVES, QUEST_ZONE_OR_SORT = 9, 10, 17
NPC_SPAWNS, NPC_ZONE = 7, 9
OBJECT_SPAWNS, OBJECT_ZONE = 4, 5
ITEM_NPC_DROPS, ITEM_OBJECT_DROPS, ITEM_ITEM_DROPS = 2, 3, 4
NAME = 1


def _cbor(data, pos=0):
    """Decodes one CBOR value -> (value, next position)."""
    head = data[pos]
    major, info = head >> 5, head & 31
    pos += 1
    if major == 7:
        if info in (20, 21):
            return info == 21, pos
        if info in (22, 23):
            return None, pos
        size, fmt = {25: (2, ">e"), 26: (4, ">f"), 27: (8, ">d")}[info]
        return struct.unpack(fmt, data[pos:pos + size])[0], pos + size
    if info < 24:
        n = info
    else:
        size = {24: 1, 25: 2, 26: 4, 27: 8}[info]
        n = int.from_bytes(data[pos:pos + size], "big")
        pos += size
    if major == 0:
        return n, pos
    if major == 1:
        return -1 - n, pos
    if major == 2:
        return data[pos:pos + n].decode("utf-8", "replace"), pos + n
    if major == 3:
        return data[pos:pos + n].decode("utf-8", "replace"), pos + n
    if major == 4:
        out = []
        for _ in range(n):
            value, pos = _cbor(data, pos)
            out.append(value)
        return out, pos
    if major == 5:
        out = {}
        for _ in range(n):
            key, pos = _cbor(data, pos)
            out[key], pos = _cbor(data, pos)
        return out, pos
    return _cbor(data, pos)     # major 6: a tag, followed by its value


def _array(value):
    """A decoded Lua array -> {index: value}. Dense arrays arrive as lists,
    sparse ones as maps keyed by their 1-based index."""
    if isinstance(value, list):
        return {i + 1: v for i, v in enumerate(value) if v is not None}
    if isinstance(value, dict):
        return {k: v for k, v in value.items() if isinstance(k, int) and v is not None}
    return {}


class QuestieDB:
    def __init__(self, addon_dir, flavor="Forever"):
        addon_dir = Path(addon_dir)
        self.raw = {}
        line_re = re.compile(r"^## (X-(?:Quest|Npc|Object|Item)-[^:]+): (.*)$")
        with open(addon_dir / ("QuestieDB_%s.toc" % flavor), encoding="utf-8") as fh:
            for line in fh:
                m = line_re.match(line.rstrip("\r\n"))
                if m:
                    self.raw[m.group(1)] = m.group(2)
        if not self.raw:
            raise SystemExit("no stored rows found in QuestieDB_%s.toc" % flavor)

        zones = addon_dir / "support" / flavor / "Zones"
        # Area id (and each of its alternate ids) -> dungeon name.
        self.dungeon_area = {}
        text = (zones / "dungeons.lua").read_text(encoding="utf-8")
        for m in re.finditer(r'^\s*\[(\d+)\] = \{"([^"]+)",(\{[\d,\s]*\}|nil),', text, re.M):
            self.dungeon_area[int(m.group(1))] = m.group(2)
            for alt in re.findall(r"\d+", m.group(3)):
                self.dungeon_area.setdefault(int(alt), m.group(2))
        # Sub-area -> parent area.
        self.parent = {}
        text = (zones / "subZoneToParentZone.lua").read_text(encoding="utf-8")
        for m in re.finditer(r"^\s*\[(\d+)\]\s*=\s*(\d+),", text, re.M):
            self.parent[int(m.group(1))] = int(m.group(2))

        # Area id -> the uiMapId it is drawn on. The file holds two tables: a
        # short list of overrides, then the full list.
        self.area_map = {}
        text = (zones / "areaIdToUiMapId.lua").read_text(encoding="utf-8")
        override, _, main = text.partition("ZoneDB.private.areaIdToUiMapId = ")
        for block in (main, override):          # overrides win
            for m in re.finditer(r"^\s*\[(\d+)\]\s*=\s*(\d+),", block, re.M):
                self.area_map[int(m.group(1))] = int(m.group(2))

        self._areas = {}

    # -- stored values -------------------------------------------------------

    def _value(self, key):
        stored = self.raw.get(key)
        if stored is None:
            return None
        parts = re.match(r"^~(\d+)~$", stored)
        if parts:
            stored = "".join(self.raw["%s-%d" % (key, i)] for i in range(1, int(parts.group(1)) + 1))
        return _cbor(base64.b64decode(stored))[0]

    def scalars(self, entity, ident):
        """{field index: value} for an entity's scalar fields."""
        return _array(self._value("X-%s-%d-S" % (entity, ident)))

    def table(self, entity, ident, field):
        return self._value("X-%s-%d-%d" % (entity, ident, field))

    def value(self, entity, ident, field):
        """One field, whether it is stored as a table or among the scalars."""
        found = self.table(entity, ident, field)
        if found is None:
            found = self.scalars(entity, ident).get(field)
        return found

    def ui_map(self, area):
        """uiMapId an area is drawn on (through its parents), or None."""
        seen = set()
        while area and area not in seen:
            seen.add(area)
            ui_map = self.area_map.get(area)
            if ui_map:
                return ui_map
            area = self.parent.get(area)
        return None

    def quest_ids(self):
        """Every quest id the database has, ascending."""
        found = set()
        for key in self.raw:
            m = re.match(r"X-Quest-(\d+)-", key)
            if m:
                found.add(int(m.group(1)))
        return sorted(found)

    def name(self, entity, ident):
        return self.scalars(entity, ident).get(NAME) or ""

    # -- where things are ----------------------------------------------------

    def dungeon_of(self, area):
        """Name of the dungeon an area id belongs to, or None."""
        seen = set()
        while area and area not in seen:
            seen.add(area)
            name = self.dungeon_area.get(area)
            if name:
                return name
            area = self.parent.get(area)
        return None

    def areas(self, entity, ident, _depth=0):
        """Every area id an NPC or object spawns in, or an item is found in."""
        key = (entity, ident)
        if key in self._areas:
            return self._areas[key]
        found = set()
        if entity in ("Npc", "Object"):
            spawns = self.table(entity, ident, NPC_SPAWNS if entity == "Npc" else OBJECT_SPAWNS)
            if isinstance(spawns, dict):
                found.update(k for k in spawns if isinstance(k, int))
            zone = self.scalars(entity, ident).get(NPC_ZONE if entity == "Npc" else OBJECT_ZONE)
            if zone:
                found.add(zone)
        elif entity == "Item":
            for npc in _array(self.table("Item", ident, ITEM_NPC_DROPS)).values():
                found |= self.areas("Npc", npc)
            for obj in _array(self.table("Item", ident, ITEM_OBJECT_DROPS)).values():
                found |= self.areas("Object", obj)
            if _depth < 2:      # an item found inside another item (a chest, a bag)
                for item in _array(self.table("Item", ident, ITEM_ITEM_DROPS)).values():
                    found |= self.areas("Item", item, _depth + 1)
        self._areas[key] = found
        return found

    def dungeons(self, areas):
        return {name for name in map(self.dungeon_of, areas) if name}

    def quest_objectives(self, quest_id):
        """[(names, areas)] for each thing a quest asks for: the lower-cased
        names it can go by, and the area ids it is found in."""
        out = []
        groups = _array(self.table("Quest", quest_id, QUEST_OBJECTIVES))
        for group, entity in ((1, "Npc"), (2, "Object"), (3, "Item")):
            for entry in _array(groups.get(group)).values():
                entry = _array(entry)
                ident = entry.get(1)
                if isinstance(ident, int):
                    names = {self.name(entity, ident).lower()}
                    if isinstance(entry.get(2), str):
                        names.add(entry[2].lower())
                    out.append((names, self.areas(entity, ident)))
        # Kill credit: several NPCs counting as one objective.
        for entry in _array(groups.get(5)).values():
            entry = _array(entry)
            names, areas = set(), set()
            if isinstance(entry.get(3), str):
                names.add(entry[3].lower())
            for ident in _array(entry.get(1)).values():
                if isinstance(ident, int):
                    names.add(self.name("Npc", ident).lower())
                    areas |= self.areas("Npc", ident)
            out.append((names, areas))
        # An "explore / escort / event" completion trigger.
        trigger = _array(self.table("Quest", quest_id, QUEST_TRIGGER_END))
        if isinstance(trigger.get(2), dict):
            names = {trigger[1].lower()} if isinstance(trigger.get(1), str) else set()
            out.append((names, {k for k in trigger[2] if isinstance(k, int)}))
        return out

    def quest_ends(self, quest_id, finish):
        """Area ids a quest's givers (finish False) or turn-ins (finish True)
        are found in: NPCs, objects, and items that start a quest."""
        areas = set()
        groups = _array(self.table(
            "Quest", quest_id, QUEST_FINISHED_BY if finish else QUEST_STARTED_BY))
        for group, entity in ((1, "Npc"), (2, "Object"), (3, "Item")):
            for ident in _array(groups.get(group)).values():
                if isinstance(ident, int):
                    areas |= self.areas(entity, ident)
        return areas

    def quest_area(self, quest_id):
        """The quest's own zone (zoneOrSort), when it is an area id."""
        zone = self.scalars("Quest", quest_id).get(QUEST_ZONE_OR_SORT)
        return zone if isinstance(zone, int) and zone > 0 else None
