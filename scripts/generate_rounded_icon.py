#!/usr/bin/env python3
"""Generate macOS-style rounded icon from source image."""

from pathlib import Path
from PIL import Image, ImageDraw

CONTENT_SIZE = 840
MACOS_ICON_SIZES = (16, 32, 64, 128, 256, 512, 1024)


def create_rounded_mask(size: int, radius: int) -> Image.Image:
    """Create a rounded rectangle mask for macOS-style icons."""
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)

    # Draw rounded rectangle
    draw.rounded_rectangle(
        [(0, 0), (size - 1, size - 1)],
        radius=radius,
        fill=255
    )

    return mask


def add_macos_rounded_corners(input_path: str, output_path: str, size: int = 1024):
    """Add macOS-style rounded corners to an icon."""
    content_size = CONTENT_SIZE
    content_offset = (size - content_size) // 2

    # macOS Big Sur uses approximately 22.37% corner radius
    corner_radius = int(content_size * 0.2237)

    # Open source image
    img = Image.open(input_path).convert('RGBA')

    # Keep the master canvas at 1024 px, but inset the artwork so Launchpad
    # does not render the rounded square larger than neighboring apps.
    img = img.resize((content_size, content_size), Image.Resampling.LANCZOS)

    # Create rounded mask
    mask = create_rounded_mask(content_size, corner_radius)

    # Apply mask
    output = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    output.paste(img, (content_offset, content_offset), mask)

    # Save
    output.save(output_path, 'PNG')
    print(f"Saved rounded icon to: {output_path}")


def generate_macos_appiconset(master_path: Path, appiconset_dir: Path):
    """Generate macOS app icon PNGs from the 1024 px master image."""
    master = Image.open(master_path).convert('RGBA')

    for icon_size in MACOS_ICON_SIZES:
        icon = master.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        output_path = appiconset_dir / f'app_icon_{icon_size}.png'
        icon.save(output_path, 'PNG')
        print(f"Saved macOS icon to: {output_path}")


if __name__ == '__main__':
    project_root = Path(__file__).resolve().parents[1]

    # Use the iOS icon with cream background
    input_file = project_root / 'assets/logo/reveric_app_icon_ios_1024.png'
    output_file = project_root / 'assets/logo/reveric_app_icon_macos_1024.png'
    appiconset_dir = project_root / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'

    add_macos_rounded_corners(input_file, output_file, 1024)
    generate_macos_appiconset(output_file, appiconset_dir)
