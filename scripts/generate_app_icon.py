"""Render the dual-gauge AppIcon.svg design with the existing Pillow dependency."""

from math import cos, hypot, radians, sin
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

root = Path(__file__).resolve().parents[1]
destination = root / "Resources/Assets.xcassets/AppIcon.appiconset"
size = 1024
sizes = (16, 32, 64, 128, 256, 512, 1024)


def rounded_mask(box, radius, width=None):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    if width is None:
        draw.rounded_rectangle(box, radius, fill=255)
    else:
        draw.rounded_rectangle(box, radius, outline=255, width=width)
    return mask


def gradient(top, bottom):
    strip = Image.new("RGBA", (1, size))
    strip.putdata([
        tuple(round(a + (b - a) * y / (size - 1)) for a, b in zip(top, bottom))
        for y in range(size)
    ])
    return strip.resize((size, size))


canvas = Image.new("RGBA", (size, size))
tile = rounded_mask((62, 62, 962, 962), 214)
shadow = Image.new("RGBA", (size, size))
shadow.putalpha(rounded_mask((78, 88, 946, 958), 206).filter(ImageFilter.GaussianBlur(22)).point(lambda a: round(a * .44)))
canvas.alpha_composite(shadow)

# A quiet reflected light, rather than a decorative white streak across the tile.
surface = Image.new("RGBA", (size, size))
pixels = surface.load()
for y in range(size):
    for x in range(size):
        light = max(0, 1 - hypot(x - 210, y - 100) / 1024) ** 2
        pixels[x, y] = (round(16 + 37 * light), round(21 + 43 * light), round(30 + 50 * light), 255)
surface.putalpha(tile)
canvas.alpha_composite(surface)
rim = gradient((210, 230, 246, 150), (108, 131, 155, 35))
rim.putalpha(Image.composite(rim.getchannel("A"), Image.new("L", (size, size)), rounded_mask((63, 63, 961, 961), 213, 3)))
canvas.alpha_composite(rim)
inner_rim = Image.new("RGBA", (size, size), (10, 14, 21, 95))
inner_rim.putalpha(rounded_mask((70, 70, 954, 954), 207, 3).point(lambda a: round(a * .38)))
canvas.alpha_composite(inner_rim)


def gauge(radius, width, end, top, bottom):
    box = (512 - radius, 512 - radius, 512 + radius, 512 + radius)
    track = Image.new("RGBA", (size, size))
    ImageDraw.Draw(track).ellipse(box, outline=(93, 116, 139, 53), width=width)
    canvas.alpha_composite(track)
    # Pillow strokes sit inside the bounding box; use their center for round caps.
    center_radius = radius - width / 2
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.arc(box, 270, end, fill=255, width=width)
    for angle in (270, end):
        x = 512 + center_radius * cos(radians(angle))
        y = 512 + center_radius * sin(radians(angle))
        half = width / 2
        draw.ellipse((x - half, y - half, x + half, y + half), fill=255)
    glow = Image.new("RGBA", (size, size), (*bottom[:3], 0))
    glow.putalpha(mask.filter(ImageFilter.GaussianBlur(15)).point(lambda a: round(a * .10)))
    canvas.alpha_composite(glow)
    color = gradient(top, bottom)
    color.putalpha(mask)
    canvas.alpha_composite(color)


gauge(306, 64, 550, (190, 232, 255, 255), (76, 158, 219, 255))
gauge(200, 58, 494, (171, 239, 216, 255), (65, 176, 145, 255))

for px in sizes:
    path = destination / f"icon-{px}.png"
    canvas.resize((px, px), Image.Resampling.LANCZOS).save(path)
    with Image.open(path) as icon:
        assert icon.mode == "RGBA" and icon.size == (px, px)
        assert icon.getpixel((0, 0))[3] == 0
        assert icon.getpixel((px // 2, px // 2))[3] == 255
        assert icon.getchannel("A").getextrema() == (0, 255)

print("Generated and checked 7 RGBA app icons (16–1024 px).")
