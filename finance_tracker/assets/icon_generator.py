"""Generate a 1024x1024 app icon: a wallet with money sticking out.

Run:  python assets/icon_generator.py
Output: assets/icon.png  (1024x1024 RGBA)
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import os

SIZE = 1024
BG_TOP = (18, 95, 115)       # deep teal
BG_BOTTOM = (8, 52, 68)      # darker teal
WALLET_BODY = (44, 48, 56)   # dark slate
WALLET_FLAP = (58, 63, 72)   # lighter slate
NOTE_GREEN = (34, 197, 94)   # emerald green
NOTE_DARK = (21, 128, 61)    # darker green
COIN_GOLD = (250, 204, 21)   # gold
COIN_GOLD_DK = (202, 138, 4)
ACCENT_WHITE = (245, 250, 255)


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def gradient_bg(size):
    """Vertical gradient background with rounded corners."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        t = y / size
        color = lerp_color(BG_TOP, BG_BOTTOM, t)
        for x in range(size):
            img.putpixel((x, y), (*color, 255))
    # Round corners (super-ellipse mask)
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, size - 1, size - 1], radius=220, fill=255)
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(img, (0, 0), mask)
    return result


def rrect(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def draw_banknote(draw, cx, cy, w, h, rotation_deg, color, dark):
    """Draw a rotated banknote (rounded rect with a circle in the middle)."""
    note = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0))
    nd = ImageDraw.Draw(note)
    nd.rounded_rectangle([20, 20, 20 + w, 20 + h], radius=18, fill=color)
    # Inner border
    nd.rounded_rectangle([28, 28, 12 + w, 12 + h], radius=12, outline=dark, width=3)
    # Center circle (like a currency emblem)
    ccx, ccy = 20 + w // 2, 20 + h // 2
    nd.ellipse([ccx - 26, ccy - 26, ccx + 26, ccy + 26], fill=dark)
    nd.ellipse([ccx - 16, ccy - 16, ccx + 16, ccy + 16], fill=color)
    note = note.rotate(rotation_deg, expand=True, resample=Image.BICUBIC)
    return note


def main():
    canvas = gradient_bg(SIZE)
    draw = ImageDraw.Draw(canvas)

    # ── Soft shadow under wallet ──
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([180, 470, 844, 880], radius=60, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas = Image.alpha_composite(canvas, shadow)
    draw = ImageDraw.Draw(canvas)

    # ── Banknotes sticking out of the wallet (behind wallet top) ──
    notes_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    # Back note (tilted left)
    n1 = draw_banknote(ImageDraw.Draw(notes_layer), 0, 0, 340, 170, -16, NOTE_DARK, (16, 100, 48))
    notes_layer.alpha_composite(n1, (300, 250))
    # Front note (tilted right)
    notes_layer2 = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    n2 = draw_banknote(ImageDraw.Draw(notes_layer2), 0, 0, 360, 180, 12, NOTE_GREEN, NOTE_DARK)
    notes_layer2.alpha_composite(n2, (300, 270))
    # Combine notes behind wallet
    canvas = Image.alpha_composite(canvas, notes_layer)
    canvas = Image.alpha_composite(canvas, notes_layer2)

    # ── Wallet body ──
    draw = ImageDraw.Draw(canvas)
    wallet_box = [200, 400, 824, 820]
    rrect(draw, wallet_box, radius=52, fill=WALLET_BODY)

    # Wallet flap (top portion, slightly lighter)
    flap_box = [200, 400, 824, 520]
    rrect(draw, flap_box, radius=52, fill=WALLET_FLAP)

    # Cover the bottom rounded corners of the flap so only top is rounded
    draw.rectangle([200, 490, 824, 520], fill=WALLET_FLAP)

    # ── Wallet stitch line (decorative) ──
    stitch_y = 515
    for x in range(230, 824, 28):
        draw.line([x, stitch_y, x + 14, stitch_y], fill=(120, 125, 135), width=3)

    # ── Wallet button / clasp on the right side ──
    clasp_cx, clasp_cy = 760, 610
    draw.ellipse([clasp_cx - 36, clasp_cy - 36, clasp_cx + 36, clasp_cy + 36],
                 fill=WALLET_FLAP, outline=(90, 95, 105), width=4)
    draw.ellipse([clasp_cx - 14, clasp_cy - 14, clasp_cx + 14, clasp_cy + 14],
                 fill=(200, 205, 215))

    # ── A gold coin on the wallet front ──
    coin_cx, coin_cy = 360, 650
    # Coin shadow
    cs = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    csd = ImageDraw.Draw(cs)
    csd.ellipse([coin_cx - 58, coin_cy - 52, coin_cx + 58, coin_cy + 64], fill=(0, 0, 0, 60))
    cs = cs.filter(ImageFilter.GaussianBlur(8))
    canvas = Image.alpha_composite(canvas, cs)
    draw = ImageDraw.Draw(canvas)
    # Coin body
    draw.ellipse([coin_cx - 55, coin_cy - 55, coin_cx + 55, coin_cy + 55],
                 fill=COIN_GOLD, outline=COIN_GOLD_DK, width=5)
    draw.ellipse([coin_cx - 38, coin_cy - 38, coin_cx + 38, coin_cy + 38],
                 outline=COIN_GOLD_DK, width=3)
    # Dollar sign on coin
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 56)
    except Exception:
        font = ImageFont.load_default()
    text = "$"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((coin_cx - tw // 2 - bbox[0], coin_cy - th // 2 - bbox[1]),
              text, fill=COIN_GOLD_DK, font=font)

    # ── Subtle highlight on wallet top edge ──
    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.rounded_rectangle([210, 405, 818, 430], radius=20, fill=(255, 255, 255, 35))
    highlight = highlight.filter(ImageFilter.GaussianBlur(6))
    canvas = Image.alpha_composite(canvas, highlight)

    out_path = os.path.join(os.path.dirname(__file__), "icon.png")
    canvas.save(out_path, "PNG")
    print(f"Saved {out_path}  ({canvas.size})")


if __name__ == "__main__":
    from PIL import ImageFont  # noqa: E402
    main()
