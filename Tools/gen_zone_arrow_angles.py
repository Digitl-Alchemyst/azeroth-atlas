"""Write Map/Data/ZoneArrowAngles.lua - which way each zone-exit arrow on
the map points (2026-11-18, user request: "the leatrix zone transfer
arrows point to the zone they are going into ours always up").

Every plain zone border in Map/Data/GuideZoneTransition.lua has two ends,
one in each zone. For each end:

  1. Leatrix Maps' own angle, when Leatrix has an arrow in the same zone,
     leading to the same zone, within 8 (map percent) of ours. Leatrix's
     angles are set by hand (Leatrix_Maps_Icons.lua, the 12th field of
     an "Arrow" row, radians for Texture:SetRotation - 0 up, counter-
     clockwise), so they follow the road, not just the border.
  2. Otherwise, an end on the very edge of its map (within 5 percent of
     one side, and only one) points straight off that side - on the 18
     edge ends Leatrix covers this lands within about 15 degrees.
  3. Otherwise, worked out: from this end towards the other end, in
     world space (Map/Data/NxMapData.lua's Scale / X / Y per zone, the
     same sums MinimapEngine:GetWorldPos does). When the two ends are
     almost on top of each other (under 10 world units apart) that
     direction means nothing, so it points away from the zone's middle.

Checked against the ends Leatrix covers: way 3 lands within about 10
degrees of Leatrix half the time. Ways 2 and 3 matter most in WoW
Forever's own zones (Riverglades, the redrawn Redridge), which Leatrix
has no arrows for.

Keys are "mapId:x:y" with x and y written the way GuideZoneTransition.
lua's addPoint writes them (Lua's %g, the same as Python's).

Run:  python -I Tools/gen_zone_arrow_angles.py   (from the addon folder,
with Leatrix_Maps installed beside it in R:\\addons)
"""
import io
import math
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.normpath(os.path.join(HERE, '..'))
LEATRIX = os.path.normpath(os.path.join(ADDON, '..', 'Leatrix_Maps', 'Leatrix_Maps_Icons.lua'))
OUT = os.path.join(ADDON, 'Map', 'Data', 'ZoneArrowAngles.lua')
MATCH = 8.0          # map percent
NEAR = 10.0          # world units
EDGE = 5.0           # map percent


def edge_angle(x, y):
    """Straight off the one side of the map the point sits on, or None."""
    sides = []
    if y <= EDGE:
        sides.append(0.0)                   # up
    if y >= 100 - EDGE:
        sides.append(math.pi)               # down
    if x <= EDGE:
        sides.append(math.pi / 2)           # left
    if x >= 100 - EDGE:
        sides.append(-math.pi / 2)          # right
    return sides[0] if len(sides) == 1 else None


def read(p):
    return io.open(p, encoding='utf-8').read()


def leatrix_arrows():
    zones, cur = {}, None
    for line in read(LEATRIX).splitlines():
        m = re.search(r'--\[\[(.*?)\]\]\s*\[(\d+)\]\s*=\s*\{', line)
        if m:
            cur = int(m.group(2))
            continue
        m = re.match(r'\s*\{"Arrow",\s*([\d.]+),\s*([\d.]+),.*,\s*([-\d.]+),\s*(\d+)\},?\s*$', line)
        if m and cur:
            zones.setdefault(cur, []).append(
                (float(m.group(1)), float(m.group(2)), float(m.group(3)), int(m.group(4))))
    return zones


def world_info():
    w = {}
    src = read(os.path.join(ADDON, 'Map', 'Data', 'NxMapData.lua'))
    for m in re.finditer(r'\[(\d+)\] = \{(.*?)\n    \}', src, re.S):
        b = m.group(2)
        sc = re.search(r'Scale = ([-\d.]+)', b)
        x = re.search(r'\bX = ([-\d.]+)', b)
        y = re.search(r'\bY = ([-\d.]+)', b)
        if sc and x and y:
            w[int(m.group(1))] = (float(sc.group(1)), float(x.group(1)), float(y.group(1)))
    return w


def borders():
    src = read(os.path.join(ADDON, 'Map', 'Data', 'GuideZoneTransition.lua'))
    pts = []
    for m in re.finditer(r'"(\d+)\|1\|\|(\d+)\|([\d.]+)\|([\d.]+)\|\|(\d+)\|([\d.]+)\|([\d.]+)"', src):
        _, z1, x1, y1, z2, x2, y2 = m.groups()
        a = (int(z1), float(x1), float(y1))
        b = (int(z2), float(x2), float(y2))
        pts.append((a, b))
        pts.append((b, a))
    return pts


def main():
    arrows = leatrix_arrows()
    W = world_info()

    def wp(z, x, y):
        s, X, Y = W[z]
        return X + x * s, Y + y * s / 1.5

    rows, from_leatrix, worked, seen = [], 0, 0, set()
    for (z, x, y), (oz, ox, oy) in borders():
        key = '%d:%s:%s' % (z, '%g' % x, '%g' % y)
        if key in seen:         # one spot, two borders: the first one wins
            continue
        seen.add(key)
        best = None
        for lx, ly, rot, dest in arrows.get(z, []):
            d = math.hypot(lx - x, ly - y)
            if dest == oz and d <= MATCH and (best is None or d < best[0]):
                best = (d, rot)
        if best:
            rot = best[1]
            from_leatrix += 1
            how = 'Leatrix'
        elif edge_angle(x, y) is not None:
            rot = edge_angle(x, y)
            worked += 1
            how = 'off the map edge'
        elif z in W and oz in W:
            ax, ay = wp(z, x, y)
            bx, by = wp(oz, ox, oy)
            dx, dy = bx - ax, by - ay
            if math.hypot(dx, dy) < NEAR:
                cx, cy = wp(z, 50, 50)
                dx, dy = ax - cx, ay - cy
                how = 'away from the middle'
            else:
                how = 'towards the other end'
            rot = math.atan2(-dx, -dy)
            worked += 1
        else:
            continue
        rows.append('    ["%s"] = %.4f,  -- to %d, %s' % (key, rot, oz, how))

    out = [
        '-- Azeroth Atlas | Map/Data/ZoneArrowAngles.lua',
        '-- GENERATED by Tools/gen_zone_arrow_angles.py - do not edit by hand.',
        '-- Which way each zone-exit arrow points: "mapId:x:y" -> radians for',
        '-- Texture:SetRotation (0 up, counter-clockwise). See the tool for how.',
        '',
        'local AzerothAtlas = _G.AzerothAtlas',
        'AzerothAtlas.Map.ZoneArrowAngles = {',
    ] + rows + ['}', '']
    io.open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
    print('wrote %s: %d from Leatrix, %d worked out' % (OUT, from_leatrix, worked))


if __name__ == '__main__':
    main()
