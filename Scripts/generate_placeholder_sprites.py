#!/usr/bin/env python3
"""Generate placeholder Orion sprites at 304x415 RGBA, matching Lenny dims."""
from PIL import Image, ImageDraw, ImageFont
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Orion", "CharacterSprites")
W, H = 304, 415

SKIN = (220, 184, 152, 255)
HAIR = (66, 50, 40, 255)
SHIRT = (62, 88, 134, 255)        # navy
PANTS = (45, 52, 64, 255)         # charcoal
SHOE = (32, 32, 38, 255)
OUTLINE = (24, 24, 28, 255)
LABEL = (200, 200, 210, 255)

def base_canvas():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))

def draw_body(d, facing, bob=0):
    cx = W // 2
    head_top = 60 + bob
    head_r = 48
    head_box = (cx - head_r, head_top, cx + head_r, head_top + 2 * head_r)
    # Hair cap (back/sides of head depending on facing)
    if facing == "back":
        d.ellipse(head_box, fill=HAIR, outline=OUTLINE, width=2)
    else:
        d.ellipse(head_box, fill=SKIN, outline=OUTLINE, width=2)
        # Hair on top
        d.pieslice(head_box, 180, 360, fill=HAIR, outline=OUTLINE, width=2)
        # Face details
        if facing == "front":
            ey = head_top + head_r + 10
            d.ellipse((cx - 18, ey - 4, cx - 10, ey + 4), fill=OUTLINE)
            d.ellipse((cx + 10, ey - 4, cx + 18, ey + 4), fill=OUTLINE)
            d.line((cx - 12, head_top + head_r + 30, cx + 12, head_top + head_r + 30), fill=OUTLINE, width=2)
        elif facing == "left":
            ey = head_top + head_r + 10
            d.ellipse((cx - 22, ey - 4, cx - 14, ey + 4), fill=OUTLINE)
            d.line((cx - 18, head_top + head_r + 30, cx - 4, head_top + head_r + 30), fill=OUTLINE, width=2)
        elif facing == "right":
            ey = head_top + head_r + 10
            d.ellipse((cx + 14, ey - 4, cx + 22, ey + 4), fill=OUTLINE)
            d.line((cx + 4, head_top + head_r + 30, cx + 18, head_top + head_r + 30), fill=OUTLINE, width=2)

    # Torso
    torso_top = head_top + 2 * head_r + 4
    torso = (cx - 52, torso_top, cx + 52, torso_top + 130)
    d.rectangle(torso, fill=SHIRT, outline=OUTLINE, width=2)

    # Arms
    arm_w = 20
    d.rectangle((cx - 52 - arm_w, torso_top + 8, cx - 52, torso_top + 110), fill=SHIRT, outline=OUTLINE, width=2)
    d.rectangle((cx + 52, torso_top + 8, cx + 52 + arm_w, torso_top + 110), fill=SHIRT, outline=OUTLINE, width=2)

    # Legs
    legs_top = torso_top + 130
    d.rectangle((cx - 50, legs_top, cx - 6, legs_top + 100), fill=PANTS, outline=OUTLINE, width=2)
    d.rectangle((cx + 6, legs_top, cx + 50, legs_top + 100), fill=PANTS, outline=OUTLINE, width=2)

    # Shoes
    d.rectangle((cx - 54, legs_top + 100, cx - 4, legs_top + 116), fill=SHOE, outline=OUTLINE, width=2)
    d.rectangle((cx + 4, legs_top + 100, cx + 54, legs_top + 116), fill=SHOE, outline=OUTLINE, width=2)

def draw_label(d, text):
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 12)
    except Exception:
        font = ImageFont.load_default()
    bbox = d.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    d.text(((W - tw) // 2, H - 22), text, fill=LABEL, font=font)

def make_static(facing, path):
    im = base_canvas()
    d = ImageDraw.Draw(im)
    draw_body(d, facing)
    draw_label(d, f"PLACEHOLDER · {facing.upper()}")
    im.save(path)
    print("wrote", path)

def make_walk_gif(facing, path):
    frames = []
    for bob in (0, -4):  # 2-frame walk bob
        im = base_canvas()
        d = ImageDraw.Draw(im)
        draw_body(d, facing, bob=bob)
        draw_label(d, f"PLACEHOLDER · WALK {facing.upper()}")
        frames.append(im)
    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=240,
        loop=0,
        disposal=2,
        transparency=0,
    )
    print("wrote", path)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_static("front", f"{OUT}/main-front.png")
    make_static("back",  f"{OUT}/main-back.png")
    make_static("left",  f"{OUT}/main-left.png")
    make_static("right", f"{OUT}/main-right.png")
    make_walk_gif("left",  f"{OUT}/lil-justin-walk-left.gif")
    make_walk_gif("right", f"{OUT}/lil-justin-walk-right.gif")
    # Remove old Lenny-named GIFs
    for old in ("lenny-walk-left.gif", "lenny-walk-right.gif"):
        p = f"{OUT}/{old}"
        if os.path.exists(p):
            os.remove(p)
            print("removed", p)
