#!/usr/bin/env python3
"""Generate a multi-size Windows ICO from the app icon source image."""

from pathlib import Path

from PIL import Image

WINDOWS_ICON_SIZES = (16, 20, 24, 28, 32, 40, 48, 56, 64, 80, 96, 128, 256)
ICON_CONTENT_RATIO = 0.88


def crop_mark(source: Image.Image) -> Image.Image:
    """Return the complete brand mark without its transparent outer padding."""
    alpha = source.getchannel('A')
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError('Windows icon source is fully transparent')
    return source.crop(bounds)


def render_icon(mark: Image.Image, size: int) -> Image.Image:
    """Render a centered mark with enough padding to avoid taskbar clipping."""
    content_size = round(size * ICON_CONTENT_RATIO)
    content = mark.copy()
    content.thumbnail((content_size, content_size), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (size, size))
    offset = (
        (size - content.width) // 2,
        (size - content.height) // 2,
    )
    canvas.alpha_composite(content, offset)
    return canvas


def generate_windows_icon(input_path: Path, output_paths: tuple[Path, ...]):
    """Generate a multi-size Windows ICO from the app mark."""
    source = Image.open(input_path).convert('RGBA')
    mark = crop_mark(source)
    frames = [render_icon(mark, size) for size in WINDOWS_ICON_SIZES]

    for output_path in output_paths:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        frames[-1].save(
            output_path,
            format='ICO',
            sizes=[(size, size) for size in WINDOWS_ICON_SIZES],
            append_images=frames[:-1],
        )
        print(f"Saved Windows icon to: {output_path}")


if __name__ == '__main__':
    project_root = Path(__file__).resolve().parents[1]
    input_file = project_root / 'assets/logo/reveric_mark_1024.png'
    output_files = (
        project_root / 'windows/runner/resources/app_icon.ico',
        project_root / 'assets/logo/reveric_app_icon_windows.ico',
    )

    generate_windows_icon(input_file, output_files)
