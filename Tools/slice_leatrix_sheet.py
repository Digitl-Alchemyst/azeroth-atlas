"""Slice Leatrix Maps' icon sheet (Gfx/Map/Leatrix_Maps.blp, 256x256) into
one named .tga per piece under Gfx/Themes/Leatrix/, for the theme library
(UI/ThemeLibrary.lua). The texture coordinates are the ones Leatrix_Maps.lua
itself uses for each piece (2026-11-17).

Needs Pillow:  python -E Tools/slice_leatrix_sheet.py
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'Gfx', 'Map', 'Leatrix_Maps.blp')
OUT = os.path.join(HERE, '..', 'Gfx', 'Themes', 'Leatrix')

# name: (left, right, top, bottom) in 0-1 texture coordinates
PIECES = {
    'ButtonBarGlow':   (0, 0.5, 0, 0.125),        # minimap button highlight
    'ButtonBar':       (0, 0.5, 0.125, 0.25),     # minimap button
    'Close':           (0, 0.125, 0.25, 0.375),   # title bar close cross
    'Maximize':        (0.125, 0.25, 0.25, 0.375),
    'Minimize':        (0.25, 0.375, 0.25, 0.375),
    'TravelAlliance':  (0, 0.125, 0.375, 0.5),    # boat / zeppelin / tram pins
    'TravelHorde':     (0.125, 0.25, 0.375, 0.5),
    'TravelNeutral':   (0.25, 0.375, 0.375, 0.5),
    'DungeonRaid':     (0.375, 0.5, 0.375, 0.5),
    'DragonGold':      (0.5, 1, 0, 0.5),          # elite-style pin frames
    'DragonSilver':    (0, 0.5, 0.5, 1),
    'DragonGrey':      (0.5, 1, 0.5, 1),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.open(SRC).convert('RGBA')
    w, h = sheet.size
    for name, (l, r, t, b) in PIECES.items():
        piece = sheet.crop((round(l * w), round(t * h), round(r * w), round(b * h)))
        path = os.path.normpath(os.path.join(OUT, name + '.tga'))
        piece.save(path)
        print('wrote', path, piece.size)


if __name__ == '__main__':
    main()
