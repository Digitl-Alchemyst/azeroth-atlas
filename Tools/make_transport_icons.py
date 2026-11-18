"""Draw Gfx/Map/IconBoat.tga, IconZeppelin.tga, IconPortal.tga and
IconTram.tga (64x64 RGBA) - the map's boat, zeppelin, portal and tram
icons (portal and tram added 2026-11-18). Drawn here (2026-11-16) so the addon
owns them: no client icon reads as a boat or a zeppelin at map size, and
Leatrix Maps uses one shared travel icon for every kind of transport.

Needs Pillow:  python -E Tools/make_transport_icons.py
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Gfx', 'Map')
S = 256                     # drawn at 4x, scaled down for smooth edges
INK = (20, 16, 12, 255)     # outline


def badge(d, fill):
    """Round badge behind the picture, so it reads on any map colour."""
    d.ellipse((6, 6, S - 6, S - 6), fill=INK)
    d.ellipse((18, 18, S - 18, S - 18), fill=fill)


def boat():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    badge(d, (38, 92, 150, 255))                       # sea blue
    # water
    d.chord((18, 150, S - 18, S - 18), 0, 180, fill=(24, 62, 112, 255))
    # hull
    hull = [(44, 158), (212, 158), (186, 196), (70, 196)]
    d.polygon([(x, y + 6) for x, y in hull], fill=INK)
    d.polygon(hull, fill=(132, 82, 40, 255))
    d.rectangle((60, 158, 196, 166), fill=(96, 58, 28, 255))
    # mast
    d.rectangle((122, 52, 134, 160), fill=INK)
    # sails
    d.polygon([(118, 58), (118, 146), (58, 146)], fill=INK)
    d.polygon([(112, 66), (112, 140), (68, 140)], fill=(240, 232, 210, 255))
    d.polygon([(138, 50), (138, 146), (198, 146)], fill=INK)
    d.polygon([(144, 60), (144, 140), (190, 140)], fill=(250, 244, 226, 255))
    # pennant
    d.polygon([(128, 36), (128, 54), (156, 45)], fill=(200, 40, 30, 255))
    return im


def zeppelin():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    badge(d, (96, 120, 150, 255))                      # sky
    # tail fins
    d.polygon([(40, 100), (14, 64), (62, 92)], fill=INK)
    d.polygon([(42, 98), (24, 70), (60, 92)], fill=(150, 40, 30, 255))
    d.polygon([(40, 132), (14, 168), (62, 140)], fill=INK)
    d.polygon([(42, 134), (24, 162), (60, 140)], fill=(150, 40, 30, 255))
    # balloon
    d.ellipse((30, 62, 230, 170), fill=INK)
    d.ellipse((38, 70, 222, 162), fill=(176, 58, 40, 255))
    # balloon bands + highlight
    for x in (84, 130, 176):
        d.line((x, 72, x, 160), fill=(120, 36, 26, 255), width=6)
    d.ellipse((70, 80, 170, 104), fill=(214, 110, 86, 255))
    # rigging
    d.line((96, 160, 108, 188), fill=INK, width=5)
    d.line((164, 160, 152, 188), fill=INK, width=5)
    # gondola
    d.rounded_rectangle((90, 182, 170, 210), radius=8, fill=INK)
    d.rounded_rectangle((96, 186, 164, 204), radius=6, fill=(120, 80, 40, 255))
    for x in (108, 124, 140, 156):
        d.rectangle((x - 4, 190, x + 2, 198), fill=(250, 210, 90, 255))
    return im


def portal():
    """A swirling mage portal in a stone arch (2026-11-18)."""
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    badge(d, (70, 44, 110, 255))                       # dusk purple
    # stone arch
    d.rounded_rectangle((58, 40, 198, 222), radius=70, fill=INK)
    d.rounded_rectangle((66, 48, 190, 214), radius=62, fill=(150, 140, 128, 255))
    # the portal itself: rings from deep violet to bright pink-white
    rings = [(76, 58, 180, 206, (90, 30, 150, 255)),
             (88, 74, 168, 196, (140, 60, 210, 255)),
             (100, 92, 156, 186, (190, 110, 240, 255)),
             (112, 110, 144, 176, (240, 200, 255, 255))]
    for x1, y1, x2, y2, c in rings:
        d.ellipse((x1, y1, x2, y2), fill=c)
    # swirl arcs
    d.arc((84, 68, 172, 200), 200, 330, fill=(250, 230, 255, 255), width=6)
    d.arc((96, 86, 160, 190), 20, 150, fill=(250, 230, 255, 255), width=5)
    # base step
    d.rectangle((70, 206, 186, 222), fill=INK)
    d.rectangle((76, 208, 180, 216), fill=(120, 110, 100, 255))
    return im


def tram():
    """A Deeprun Tram car on its rail (2026-11-18)."""
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    badge(d, (60, 70, 80, 255))                        # tunnel grey
    # rail
    d.rectangle((24, 190, S - 24, 202), fill=INK)
    d.rectangle((30, 192, S - 30, 198), fill=(170, 170, 176, 255))
    # car body
    d.rounded_rectangle((46, 78, 210, 184), radius=18, fill=INK)
    d.rounded_rectangle((54, 86, 202, 176), radius=12, fill=(196, 150, 54, 255))
    # roof stripe
    d.rectangle((54, 96, 202, 106), fill=(150, 104, 30, 255))
    # windows
    for x in (66, 108, 150):
        d.rounded_rectangle((x, 114, x + 34, 146), radius=5, fill=INK)
        d.rounded_rectangle((x + 4, 118, x + 30, 142), radius=4, fill=(150, 210, 240, 255))
    # wheels
    for x in (84, 172):
        d.ellipse((x - 18, 168, x + 18, 204), fill=INK)
        d.ellipse((x - 11, 175, x + 11, 197), fill=(110, 110, 116, 255))
    # pantograph to the overhead cable
    d.line((128, 78, 112, 48), fill=INK, width=6)
    d.line((112, 48, 148, 48), fill=INK, width=6)
    return im


def save(im, name):
    path = os.path.normpath(os.path.join(OUT, name))
    im.resize((64, 64), Image.LANCZOS).save(path)
    print('wrote', path)


if __name__ == '__main__':
    save(boat(), 'IconBoat.tga')
    save(zeppelin(), 'IconZeppelin.tga')
    save(portal(), 'IconPortal.tga')
    save(tram(), 'IconTram.tga')
