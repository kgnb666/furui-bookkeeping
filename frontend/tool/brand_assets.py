# -*- coding: utf-8 -*-
"""从「福瑞记账」品牌图生成 App 图标与品牌图片资源。

用法：python tool/brand_assets.py

输入：品牌设计图（1024x1536，橙黄圆角图标 + 字标 + 标语）
输出：assets/brand/*.png，供 flutter_launcher_icons 与页面使用。
"""

import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SOURCE = r"C:\Users\kgnb666.DESKTOP-55DCFH3.003\Desktop\e496afc4-91f0-4490-a4cc-aed787e7a559.png"

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "assets", "brand")
ANDROID_SPLASH_DIR = os.path.join(
    ROOT, "android", "app", "src", "main", "res", "drawable-nodpi"
)


def is_background(px):
    """判断像素是否属于奶油白背景。"""
    r, g, b = px[:3]
    return r > 235 and g > 228 and b > 205


def find_icon_box(im):
    """扫描出橙色圆角图标的左右边界；上下边界由第一行内容与宽高比推出。"""
    w, h = im.size
    rgb = im.convert("RGB")

    def row_span(y):
        """这一行上非背景像素的左右边界，没有内容时返回 None。"""
        xs = [x for x in range(0, w, 2) if not is_background(rgb.getpixel((x, y)))]
        return (xs[0], xs[-1]) if xs else None

    spans = {y: row_span(y) for y in range(h)}

    top = next(y for y in range(h) if spans[y])
    # 设计稿中圆角图标为正方形，用图标区内的最大行宽作为边长即可框出整个图标
    limit = round(h * 0.55)
    side = max(spans[y][1] - spans[y][0] for y in range(top, limit) if spans[y])
    left = min(spans[y][0] for y in range(top, min(top + side, h)) if spans[y])
    # 图标底边与字标之间留有空隙，把窗口整体上移一点让招财猫更居中
    return left, max(top - side // 33, 0), left + side, max(top - side // 33, 0) + side


def square_icon(im, box):
    """把图标区域裁成正方形，四周留出安全边距。"""
    left, top, right, bottom = box
    side = max(right - left, bottom - top)
    cx = (left + right) / 2
    cy = (top + bottom) / 2
    half = side / 2
    return im.crop(
        (round(cx - half), round(cy - half), round(cx + half), round(cy + half))
    )


def rounded(im, radius_ratio=0.22):
    """生成圆角遮罩，模拟设计稿里的圆角方块。"""
    size = im.size[0]
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=int(size * radius_ratio), fill=255
    )
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def trim_background(im, tolerance=12):
    """按背景色裁掉四周空白，用于字标一类的图片。"""
    rgb = im.convert("RGB")
    bg = Image.new("RGB", rgb.size, rgb.getpixel((0, 0)))
    diff = ImageChops.difference(rgb, bg).convert("L").point(lambda v: 255 if v > tolerance else 0)
    box = diff.getbbox()
    return im.crop(box) if box else im


def save(im, name, size=None):
    if size:
        im = im.resize((size, size), Image.LANCZOS)
    path = os.path.join(OUT_DIR, name)
    im.save(path)
    print(f"  {name:<28} {im.size[0]}x{im.size[1]}")


def dominant_colors(im, limit=6):
    """统计主要配色，用于确认品牌色值。"""
    small = im.convert("RGB").resize((160, 160))
    counts = {}
    for px in small.getdata():
        key = (px[0] // 12 * 12, px[1] // 12 * 12, px[2] // 12 * 12)
        counts[key] = counts.get(key, 0) + 1
    top = sorted(counts.items(), key=lambda kv: -kv[1])[:limit]
    return ["#%02X%02X%02X" % k for k, _ in top]


def main():
    source = SOURCE if len(sys.argv) < 2 else sys.argv[1]
    if not os.path.exists(source):
        print(f"找不到品牌图：{source}", file=sys.stderr)
        return 1

    os.makedirs(OUT_DIR, exist_ok=True)
    im = Image.open(source).convert("RGB")
    print(f"品牌图 {im.size[0]}x{im.size[1]}  主要配色 {dominant_colors(im)}")

    box = find_icon_box(im)
    print(f"图标区域 {box}")

    icon = square_icon(im, box)
    print("生成资源：")

    # App 图标：满幅方形，交给 flutter_launcher_icons 适配各平台
    save(icon, "app_icon.png", 1024)
    # 自适应图标前景：留出安全区，避免被系统裁掉
    safe = Image.new("RGB", (icon.size[0], icon.size[1]), icon.getpixel((4, 4)))
    inner = icon.resize((int(icon.size[0] * 0.82), int(icon.size[0] * 0.82)), Image.LANCZOS)
    offset = (icon.size[0] - inner.size[0]) // 2
    safe.paste(inner, (offset, offset))
    save(rounded(safe), "app_icon_foreground.png", 1024)
    # 圆角图标：页面内展示用
    save(rounded(icon), "app_icon_rounded.png", 512)

    # 页面用品牌插画：图标 + 字标 + 标语
    poster = trim_background(im)
    save(poster, "brand_poster.png")
    save(rounded(icon), "brand_logo.png", 256)

    # Android 启动页：png 放在 nodpi 目录，避免被按密度放大
    os.makedirs(ANDROID_SPLASH_DIR, exist_ok=True)
    splash = rounded(icon).resize((384, 384), Image.LANCZOS)
    splash_path = os.path.join(ANDROID_SPLASH_DIR, "splash_logo.png")
    splash.save(splash_path)
    print(f"  {'android/.../splash_logo.png':<28} {splash.size[0]}x{splash.size[1]}")

    print(f"\n输出目录：{OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
