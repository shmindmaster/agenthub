from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
SCALE = 4
SIZE = 512


def s(value: float) -> int:
    return round(value * SCALE)


def interpolate(start: tuple[int, int, int], end: tuple[int, int, int], amount: float):
    return tuple(round(a + (b - a) * amount) for a, b in zip(start, end))


def render(filename: str, start: tuple[int, int, int], end: tuple[int, int, int]):
    image = Image.new("RGBA", (s(SIZE), s(SIZE)), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    for y in range(s(16), s(496)):
        amount = (y - s(16)) / s(480)
        color = interpolate(start, end, amount) + (255,)
        draw.line((s(16), y, s(496), y), fill=color, width=1)

    mask = Image.new("L", image.size, 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((s(16), s(16), s(496), s(496)), radius=s(120), fill=255)
    image.putalpha(mask)
    draw = ImageDraw.Draw(image)

    segments = [
        ((160, 128), (352, 128)),
        ((384, 160), (384, 352)),
        ((352, 384), (160, 384)),
        ((128, 352), (128, 160)),
    ]
    colors = [(109, 143, 255), (50, 214, 197), (247, 200, 91), (167, 139, 250)]
    for (start_point, end_point), color in zip(segments, colors):
        draw.line(tuple(s(v) for point in (start_point, end_point) for v in point), fill=color + (255,), width=s(24))

    nodes = [((160, 128), colors[0]), ((384, 160), colors[1]), ((352, 384), colors[2]), ((128, 352), colors[3])]
    for (x, y), color in nodes:
        draw.ellipse((s(x - 32), s(y - 32), s(x + 32), s(y + 32)), fill=color + (255,))

    star = [(256, 176), (278, 234), (336, 256), (278, 278), (256, 336), (234, 278), (176, 256), (234, 234)]
    draw.polygon([(s(x), s(y)) for x, y in star], fill=(248, 250, 252, 255))
    draw.ellipse((s(236), s(236), s(276), s(276)), fill=(79, 124, 255, 255))

    image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(ASSETS / filename, optimize=True)


if __name__ == "__main__":
    ASSETS.mkdir(parents=True, exist_ok=True)
    render("product-experience-engineering.png", (32, 42, 85), (16, 20, 38))
    render("product-experience-engineering-dark.png", (24, 31, 65), (7, 10, 22))
    print("Rendered Product Experience Engineering brand assets.")
