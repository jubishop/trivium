#!/usr/bin/env python3
"""Generate Trivium app icon: three speech bubbles in a triangular formation."""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math
import json
import os

def create_icon(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Rounded rect background - dark slate
    margin = int(size * 0.05)
    corner = int(size * 0.18)
    bg_rect = [margin, margin, size - margin, size - margin]

    # Draw rounded rectangle background
    draw.rounded_rectangle(bg_rect, radius=corner, fill=(30, 32, 40, 255))

    # Subtle gradient overlay (lighter at top)
    overlay = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(overlay)
    for y in range(margin, size - margin):
        alpha = int(40 * (1 - (y - margin) / (size - 2 * margin)))
        odraw.line([(margin, y), (size - margin, y)], fill=(255, 255, 255, alpha))
    img = Image.alpha_composite(img, overlay)
    draw = ImageDraw.Draw(img)

    cx, cy = size / 2, size / 2 + size * 0.02
    spread = size * 0.16

    # Three bubble configs: color, position angle
    bubbles = [
        ((255, 160, 50, 255),  -90),   # orange (top) - Claude
        ((80, 200, 120, 255),  150),    # green (bottom-left) - Codex
        ((100, 160, 255, 255), 30),     # blue (bottom-right) - User
    ]

    bubble_r = size * 0.18

    # Draw bubbles with slight overlap
    for color, angle_deg in bubbles:
        angle = math.radians(angle_deg)
        bx = cx + spread * math.cos(angle)
        by = cy + spread * math.sin(angle)

        # Shadow
        shadow_offset = size * 0.01
        draw.ellipse(
            [bx - bubble_r + shadow_offset, by - bubble_r + shadow_offset,
             bx + bubble_r + shadow_offset, by + bubble_r + shadow_offset],
            fill=(0, 0, 0, 60)
        )

        # Bubble
        draw.ellipse(
            [bx - bubble_r, by - bubble_r, bx + bubble_r, by + bubble_r],
            fill=color
        )

        # Speech tail pointing outward
        tail_angle = angle
        tail_len = size * 0.08
        tail_width = size * 0.05
        tip_x = bx + (bubble_r + tail_len * 0.3) * math.cos(tail_angle)
        tip_y = by + (bubble_r + tail_len * 0.3) * math.sin(tail_angle)
        base1_x = bx + bubble_r * 0.7 * math.cos(tail_angle + 0.35)
        base1_y = by + bubble_r * 0.7 * math.sin(tail_angle + 0.35)
        base2_x = bx + bubble_r * 0.7 * math.cos(tail_angle - 0.35)
        base2_y = by + bubble_r * 0.7 * math.sin(tail_angle - 0.35)
        draw.polygon(
            [(tip_x, tip_y), (base1_x, base1_y), (base2_x, base2_y)],
            fill=color
        )

        # Inner highlight (small lighter ellipse)
        highlight_r = bubble_r * 0.5
        hx = bx - bubble_r * 0.15
        hy = by - bubble_r * 0.2
        lighter = tuple(min(255, c + 60) for c in color[:3]) + (80,)
        draw.ellipse(
            [hx - highlight_r, hy - highlight_r, hx + highlight_r, hy + highlight_r],
            fill=lighter
        )

    # Draw small dots inside each bubble to suggest text/chat
    for color, angle_deg in bubbles:
        angle = math.radians(angle_deg)
        bx = cx + spread * math.cos(angle)
        by = cy + spread * math.sin(angle) + size * 0.02

        dot_r = size * 0.02
        dot_spacing = size * 0.055
        for i in range(3):
            dx = bx + (i - 1) * dot_spacing
            dy = by
            draw.ellipse(
                [dx - dot_r, dy - dot_r, dx + dot_r, dy + dot_r],
                fill=(255, 255, 255, 200)
            )

    return img


output_dir = os.path.expanduser(
    "~/Desktop/trivium/Trivium/Assets.xcassets/AppIcon.appiconset"
)

# Pixel sizes needed: 1x and 2x for each logical size
size_specs = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

# Generate at 1024 then downscale for quality
master = create_icon(1024)

for pixel_size, filename in size_specs:
    resized = master.resize((pixel_size, pixel_size), Image.LANCZOS)
    resized.save(os.path.join(output_dir, filename))
    print(f"  {filename} ({pixel_size}x{pixel_size})")

# Update Contents.json
contents = {
    "images": [
        {"idiom": "mac", "scale": "1x", "size": "16x16", "filename": "icon_16x16.png"},
        {"idiom": "mac", "scale": "2x", "size": "16x16", "filename": "icon_16x16@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "32x32", "filename": "icon_32x32.png"},
        {"idiom": "mac", "scale": "2x", "size": "32x32", "filename": "icon_32x32@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "128x128", "filename": "icon_128x128.png"},
        {"idiom": "mac", "scale": "2x", "size": "128x128", "filename": "icon_128x128@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "256x256", "filename": "icon_256x256.png"},
        {"idiom": "mac", "scale": "2x", "size": "256x256", "filename": "icon_256x256@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "512x512", "filename": "icon_512x512.png"},
        {"idiom": "mac", "scale": "2x", "size": "512x512", "filename": "icon_512x512@2x.png"},
    ],
    "info": {"author": "xcode", "version": 1},
}

with open(os.path.join(output_dir, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)
    f.write("\n")

print("Done! Contents.json updated.")
