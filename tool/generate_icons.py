#!/usr/bin/env python3
"""生成「轻云」应用图标与启动页标记（可重复运行）。

设计：蓝色渐变圆角方块 + 白色云朵（柔和渐变 + 投影）+ 琥珀色对勾。
- iOS：`ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`（不透明、无圆角，由系统裁切）
- iOS 启动页：`Assets.xcassets/LaunchMark.imageset/*`（96pt，带圆角）
- Android：`mipmap-*/ic_launcher.png`（旧版，带圆角）+ 自适应图标的前景/背景层
- Android 启动页：`drawable-*/ic_splash_logo.png`（120dp，带圆角）

用法：python3 tool/generate_icons.py
依赖：Pillow
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANDROID_RES = os.path.join(ROOT, "android/app/src/main/res")
IOS_ASSETS = os.path.join(ROOT, "ios/Runner/Assets.xcassets")

CHECK_COLOR = (255, 178, 36)      # 琥珀色对勾（呼应参考图的暖色点缀）
BG_TOP = (58, 156, 255)
BG_BOTTOM = (0, 96, 240)

CHECK_PTS = [(0.355, 0.595), (0.465, 0.695), (0.655, 0.465)]
CHECK_W = 0.078


# ---------------------------------------------------------------- shapes

def _cloud(draw, color, size):
    def circle(cx, cy, r):
        draw.ellipse(
            [(cx - r) * size, (cy - r) * size, (cx + r) * size, (cy + r) * size],
            fill=color,
        )

    def rrect(x0, y0, x1, y1, r):
        draw.rounded_rectangle(
            [x0 * size, y0 * size, x1 * size, y1 * size],
            radius=r * size,
            fill=color,
        )

    circle(0.400, 0.540, 0.245)
    circle(0.665, 0.585, 0.170)
    rrect(0.155, 0.540, 0.815, 0.795, 0.128)


def _check(draw, color, size):
    xy = [(x * size, y * size) for x, y in CHECK_PTS]
    draw.line(xy, fill=color, width=int(CHECK_W * size), joint="curve")
    for x, y in (xy[0], xy[-1]):
        r = int(CHECK_W * size / 2)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


def _gradient(size):
    img = Image.new("RGB", (size, size), BG_TOP)
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = (y / (size - 1)) ** 0.85
        d.line(
            [(0, y), (size, y)],
            fill=tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)),
        )
    # 左上角柔光
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse(
        [-0.35 * size, -0.45 * size, 0.75 * size, 0.65 * size], fill=36
    )
    mask = mask.filter(ImageFilter.GaussianBlur(size * 0.12))
    return Image.composite(Image.new("RGB", (size, size), (255, 255, 255)), img, mask)


def _cloud_art(size):
    """透明画布上的「云 + 对勾」（用于自适应图标前景 / 单色层）。"""
    art = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 投影
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    _cloud(ImageDraw.Draw(shadow), (0, 52, 140, 110), size)
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.030))
    shadow = shadow.transform(
        shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, size * 0.022)
    )
    art.alpha_composite(shadow)

    # 云朵本体：竖直渐变 + 顶部高光
    mask = Image.new("L", (size, size), 0)
    _cloud(ImageDraw.Draw(mask), 255, size)
    grad = Image.new("RGB", (size, size), (255, 255, 255))
    gd = ImageDraw.Draw(grad)
    top, bottom = (255, 255, 255), (240, 247, 255)
    for y in range(size):
        t = max(0.0, min(1.0, (y / size - 0.30) / 0.55))
        gd.line(
            [(0, y), (size, y)],
            fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    art.paste(grad, (0, 0), mask)

    hi = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(hi).ellipse(
        [0.18 * size, 0.30 * size, 0.72 * size, 0.62 * size],
        fill=(255, 255, 255, 46),
    )
    hi = hi.filter(ImageFilter.GaussianBlur(size * 0.05))
    art.alpha_composite(
        Image.composite(hi, Image.new("RGBA", (size, size), (0, 0, 0, 0)), mask)
    )

    _check(ImageDraw.Draw(art), CHECK_COLOR + (255,), size)
    return art


def _shrink(img, factor):
    """把透明画布上的图形等比缩小并居中。"""
    size = img.size[0]
    inner = int(size * factor)
    small = img.resize((inner, inner), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    canvas.alpha_composite(small, (off, off))
    return canvas


def render_icon(size, rounded=True, with_bg=True):
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if with_bg:
        bg = _gradient(size)
        if rounded:
            mask = Image.new("L", (size, size), 0)
            ImageDraw.Draw(mask).rounded_rectangle(
                [0, 0, size - 1, size - 1], radius=int(size * 0.2237), fill=255
            )
            canvas.paste(bg, (0, 0), mask)
        else:
            canvas.paste(bg, (0, 0))
    canvas.alpha_composite(_cloud_art(size))
    return canvas


# ---------------------------------------------------------------- export helpers

def _save(img, path, size=None, rgb=False):
    if size:
        img = img.resize((size, size), Image.LANCZOS)
    if rgb:
        flat = Image.new("RGB", img.size, (255, 255, 255))
        flat.paste(img, (0, 0), img)
        img = flat
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


def export_ios():
    appicon = os.path.join(IOS_ASSETS, "AppIcon.appiconset")
    # (filename, pixel size) —— 与 Contents.json 一一对应
    ios_icons = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    master = render_icon(2048, rounded=False)
    for name, px in ios_icons.items():
        _save(master, os.path.join(appicon, name), size=px, rgb=True)

    # 启动页标记：带圆角，与桌面图标一致
    rounded = render_icon(1200, rounded=True)
    mark = os.path.join(IOS_ASSETS, "LaunchMark.imageset")
    _save(rounded, os.path.join(mark, "LaunchMark.png"), size=96)
    _save(rounded, os.path.join(mark, "LaunchMark@2x.png"), size=192)
    _save(rounded, os.path.join(mark, "LaunchMark@3x.png"), size=288)


def export_android():
    # 旧版图标（API < 26 与部分启动器）
    for density, px in {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }.items():
        _save(
            render_icon(1024, rounded=True),
            os.path.join(ANDROID_RES, f"mipmap-{density}/ic_launcher.png"),
            size=px,
        )

    # 自适应图标：背景层（渐变）+ 前景层（云 + 对勾，落在 72/108 安全区内）
    for density, px in {
        "mdpi": 108,
        "hdpi": 162,
        "xhdpi": 216,
        "xxhdpi": 324,
        "xxxhdpi": 432,
    }.items():
        base = os.path.join(ANDROID_RES, f"mipmap-{density}")
        _save(_gradient(1024), os.path.join(base, "ic_launcher_background.png"), size=px)
        # 前景缩到 70%：自适应图标可见区只有 72/108，且部分启动器（ColorOS）会二次放大前景
        _save(_shrink(_cloud_art(1024), 0.70), os.path.join(base, "ic_launcher_foreground.png"), size=px)

    # 启动页图标（120dp，带圆角）
    for density, px in {
        "mdpi": 120,
        "hdpi": 180,
        "xhdpi": 240,
        "xxhdpi": 360,
        "xxxhdpi": 480,
    }.items():
        splash = render_icon(1200, rounded=True)
        _save(
            splash,
            os.path.join(ANDROID_RES, f"drawable-{density}/ic_splash_logo.png"),
            size=px,
        )
        # Android 12+ 的系统启动页会把图标放大到图标区，用 62% 内缩版本留出安全区
        _save(
            _shrink(splash, 0.62),
            os.path.join(ANDROID_RES, f"drawable-{density}/ic_splash_logo_padded.png"),
            size=px,
        )


def export_preview():
    """预览图（不参与构建）：不同尺寸下的观感。"""
    icon = render_icon(1200, rounded=True)
    sheet = Image.new("RGB", (900, 240), (242, 242, 247))
    x = 24
    for px in (160, 96, 64, 40):
        sheet.paste(icon.resize((px, px), Image.LANCZOS), (x, (240 - px) // 2))
        x += px + 34
    sheet.save(os.path.join("/tmp", "qingyun_icon_preview.png"))


if __name__ == "__main__":
    export_ios()
    export_android()
    export_preview()
    print("icons + splash marks generated")
