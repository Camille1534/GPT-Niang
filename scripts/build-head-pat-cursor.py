"""Convert the approved two-cell PNG sprite sheet to Windows cursors (Pillow)."""
from pathlib import Path
import struct
from PIL import Image

assets = Path(__file__).resolve().parents[1] / 'gpt-niang-usage/assets'
sheet = Image.open(assets / 'head-pat-states.png').convert('RGBA')
assert sheet.width == sheet.height * 2
for cell, name in enumerate(('head-pat-cursor.cur', 'head-pat-pressed.cur')):
    sprite = sheet.crop((cell * sheet.height, 0, (cell + 1) * sheet.height, sheet.height))
    frames = []
    for size in (32, 48, 64, 96):
        bitmap = sprite.resize((size, size), Image.Resampling.LANCZOS)
        stride = ((size + 31) // 32) * 4
        mask = bytearray(stride * size)
        for y in range(size):
            for x in range(size):
                if bitmap.getpixel((x, y))[3] == 0:
                    mask[(size - 1 - y) * stride + x // 8] |= 128 >> (x % 8)
        dib = struct.pack('<IiiHHIIiiII', 40, size, size * 2, 1, 32, 0, size * size * 4 + len(mask), 0, 0, 0, 0)
        frames.append((size, dib + bitmap.tobytes('raw', 'BGRA', 0, -1) + mask))
    offset = 6 + 16 * len(frames)
    directory = bytearray(struct.pack('<HHH', 0, 2, len(frames)))
    for size, data in frames:
        directory += struct.pack('<BBBBHHII', size, size, 0, 0, round(6 * size / 32), round(21 * size / 32), len(data), offset)
        offset += len(data)
    (assets / name).write_bytes(directory + b''.join(data for _, data in frames))
    print('Built', name)
