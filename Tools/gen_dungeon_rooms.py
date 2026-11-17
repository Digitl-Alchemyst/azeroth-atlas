"""Generate Map/Data/DungeonRoomData.lua - the named rooms of every dungeon
and raid, for "you are in this room" inside instances (Map/DungeonRooms.lua).

Source: Forever Dungeon Routes by Checkov23 (MIT license,
github.com/Checkov23/ForeverDungeonRoutes) - Data/Dungeons.lua,
Data/Rooms.lua, Data/Pictures.lua. Levels of WoW Forever's own dungeons
are matched to Forever Dungeon Journal's art (Core/Journal.lua,
DUNGEON_MAPS) by picture name; a level with no matching picture is left
out, so no room is drawn on art it doesn't belong to.

Usage:
  python -I Tools/gen_dungeon_rooms.py <FDR ForeverDungeonRoutes folder or
      folder holding Dungeons.lua, Rooms.lua, Pictures.lua> <FDJ folder>
"""
import io
import os
import re
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Map', 'Data', 'DungeonRoomData.lua')
CLIENT_MAX = 1000000          # FDR's own picture floors are 10xxxxx

# FDR picture name -> FDJ picture name where the two addons name the same
# picture differently. Checked pixel for pixel 2026-11-16 (grey-level
# correlation of the map area: 1.000 for each pair below; different
# pictures of the same dungeon score 0.3-0.4).
SAME_PICTURE = {
    'blackmawhold': 'blackmawholdgrove',
    'alcazprisonmaximumsecurity': 'alcazprisonmap2',
    'dalaran': 'dalarancity',
}


def read(path):
    return io.open(path, encoding='utf-8').read()


def find(folder, name):
    for cand in (os.path.join(folder, name), os.path.join(folder, 'Data', name)):
        if os.path.exists(cand):
            return cand
    raise SystemExit('missing ' + name)


def norm(s):
    s = s.lower().replace('\\\\', '\\').split('\\')[-1]
    s = re.sub(r'map$', '', s)
    return re.sub(r'[^a-z0-9]', '', s)


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


ROOM_RE = re.compile(r'\{ name = "((?:[^"\\]|\\.)*)"[^\n]*?boxes = \{ (.*?) \} \}')
# No closing brace: the room pattern above ends its match on the last
# box's "} }", taking that brace with it.
BOX_RE = re.compile(r'\{ (\d+), ([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.e]+)')


def parse_rooms_block(text):
    rooms = []
    for m in ROOM_RE.finditer(text):
        boxes = [tuple(float(x) if i else int(x) for i, x in enumerate(b.groups()))
                 for b in BOX_RE.finditer(m.group(2))]
        rooms.append((m.group(1).replace('\\"', '"'), boxes))
    return rooms


def main(fdr, fdj):
    dungeons = []
    for m in re.finditer(r'\{ key = "([a-z_]+)", instanceID = (\d+), floors = \{ ([\d, ]+) \}', read(find(fdr, 'Dungeons.lua'))):
        dungeons.append((m.group(1), int(m.group(2)), [int(x) for x in m.group(3).split(',')]))

    rooms = {}
    text = read(find(fdr, 'Rooms.lua'))
    for m in re.finditer(r'^\t([a-z_]+) = \{\n(.*?)^\t\},', text, re.S | re.M):
        rooms[m.group(1)] = parse_rooms_block(m.group(2))
    pics = read(find(fdr, 'Pictures.lua'))
    for m in re.finditer(r'^DR\.Rooms\.([a-z_]+) = \{\n(.*?)^\}', pics, re.S | re.M):
        rooms.setdefault(m.group(1), []).extend(parse_rooms_block(m.group(2)))
    images = {int(m.group(1)): norm(m.group(2)) for m in re.finditer(
        r'DR\.Floors\[(\d+)\] = \{.*?image = \{ file = "([^"]+)"', pics, re.S)}
    # FDR's own levels drawn from the game's old world map tiles (twelve
    # file ids, 4 across 3 down) - Upper Blackrock Spire's three.
    tile_floors = {}
    for m in re.finditer(r'^\t\[(\d+)\] = \{ name = "((?:[^"\\]|\\.)*)".*?\n\t\ttiles = \{ ([\d, ]+) \}',
                         read(find(fdr, 'Floors.lua')), re.M):
        fid = int(m.group(1))
        if fid >= CLIENT_MAX:
            tile_floors[fid] = (m.group(2), [int(x) for x in m.group(3).split(',')])

    journal = read(os.path.join(fdj, 'Core', 'Journal.lua'))
    inst_name = {}
    m = re.search(r'INSTANCE_ID_TO_DUNGEON = \{(.*?)\n\}', journal, re.S)
    for im in re.finditer(r'\[(\d+)\] = "([^"]+)"', m.group(1)):
        inst_name[int(im.group(1))] = im.group(2)
    fdj_floors = {}
    for em in re.finditer(r'^    \["([^"]+)"\] = \{\n(.*?)(?=^    \["|^\}\n)', journal, re.S | re.M):
        body = em.group(2)
        cut = min([i for i in (body.find('entrance ='), body.find('transitions ='), body.find('bosses =')) if i >= 0] or [len(body)])
        tex = [norm(t) for t in re.findall(r'\btexture = "([^"]+)"', body[:cut])]
        if tex:
            fdj_floors.setdefault(em.group(1), tex)

    out_rooms, client_floors, fdr_keys, report, out_tiles = {}, {}, {}, [], {}
    for key, inst, floors in dungeons:
        fdr_keys[key] = inst
        for f in floors:
            if f < CLIENT_MAX:
                client_floors.setdefault(inst, [])
                if f not in client_floors[inst]:
                    client_floors[inst].append(f)
        # Forever picture floor -> FDJ level index
        level_of = {}
        name = inst_name.get(inst)
        tex = fdj_floors.get(name) or fdj_floors.get(('The ' + name) if name else None) or []
        for f in floors:
            if f in tile_floors:
                out_tiles.setdefault(inst, []).append((f,) + tile_floors[f])
                level_of[f] = f            # kept as is: the engine knows it by this id
                continue
            img = images.get(f)
            img = SAME_PICTURE.get(img, img)
            if f >= CLIENT_MAX and img in tex:
                level_of[f] = tex.index(img) + 1
            elif f >= CLIENT_MAX:
                report.append('%s: level %d (%s) has no matching FDJ art - left out' % (key, f, images.get(f)))
        for rname, boxes in rooms.get(key, []):
            kept = []
            for b in boxes:
                if b[0] < CLIENT_MAX:
                    kept.append(b)
                elif b[0] in level_of:
                    kept.append((level_of[b[0]],) + b[1:])
            if kept:
                out_rooms.setdefault(inst, []).append((rname, kept))

    lines = [
        '-- GENERATED by Tools/gen_dungeon_rooms.py - do not edit by hand.',
        '-- Room data: Forever Dungeon Routes by Checkov23, MIT license',
        '-- (github.com/Checkov23/ForeverDungeonRoutes); license text in',
        '-- Map/DungeonRooms.lua. Generated there from the game\'s own building',
        '-- files (WMOAreaTable names, WMO group boxes).',
        '--',
        '-- Rooms[instanceID] = { { name, { level, u, v, width, height }, ... } }',
        '--   level < 100: level index of a Forever Dungeon Journal map;',
        '--   otherwise the game\'s uiMapID. u, v: box centre (0-1 on that map);',
        '--   width, height: pixels of the 1002x668 map.',
        '-- ClientFloors[instanceID] = the game\'s maps of an instance, in order',
        '--   (used when the game names no map inside it).',
        '-- TileFloors[instanceID] = extra levels drawn from the game\'s old world',
        '--   map tiles (12 file ids, 4 across 3 down, map = top-left 1002x668);',
        '--   rooms on them carry the level\'s id.',
        '-- FDRKeys[key] = instanceID: Forever Dungeon Routes\' dungeon keys,',
        '--   for its party room messages.',
        'local AlchemyGPS = _G.AlchemyGPS',
        'AlchemyGPS.DungeonRoomData = {',
        '    Rooms = {',
    ]
    for inst in sorted(out_rooms):
        lines.append('        [%d] = {' % inst)
        for rname, boxes in out_rooms[inst]:
            bs = ', '.join('{ %d, %.4f, %.4f, %.1f, %.1f }' % b[:5] for b in boxes)
            lines.append('            { %s, %s },' % (lua_str(rname), bs))
        lines.append('        },')
    lines.append('    },')
    lines.append('    ClientFloors = {')
    for inst in sorted(client_floors):
        lines.append('        [%d] = { %s },' % (inst, ', '.join(str(f) for f in client_floors[inst])))
    lines.append('    },')
    lines.append('    TileFloors = {')
    for inst in sorted(out_tiles):
        lines.append('        [%d] = {' % inst)
        for fid, name, tiles in out_tiles[inst]:
            lines.append('            { id = %d, name = %s, tiles = { %s } },' % (fid, lua_str(name), ', '.join(str(t) for t in tiles)))
        lines.append('        },')
    lines.append('    },')
    lines.append('    FDRKeys = {')
    for key in sorted(fdr_keys):
        lines.append('        %s = %d,' % (key, fdr_keys[key]))
    lines.append('    },')
    lines.append('}')
    io.open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
    n = sum(len(v) for v in out_rooms.values())
    print('%d rooms in %d instances -> %s' % (n, len(out_rooms), os.path.normpath(OUT)))
    for r in report:
        print('  ' + r)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
