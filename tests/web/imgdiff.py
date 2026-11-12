"""Tiny stdlib PNG decoder + region diff, used to tell whether the 3D view changed between two screenshots."""
import struct
import zlib


def decode_png(data: bytes):
    """Returns (width, height, channels, rows) where rows is a list of bytearrays (8-bit PNGs only)."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, w, h, ctype = 8, b"", 0, 0, 2
    while pos < len(data):
        n, = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * ch
    rows, prev = [], bytearray(stride)
    i = 0
    for _ in range(h):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        if f == 1:
            for x in range(ch, stride):
                line[x] = (line[x] + line[x - ch]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                b = prev[x]
                c = prev[x - ch] if x >= ch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(line)
        prev = line
    return w, h, ch, rows


def region_diff(png_a: bytes, png_b: bytes, box, step: int = 2) -> float:
    """Mean absolute RGB difference (0-255) inside box=(x0,y0,x1,y1) in pixels."""
    wa, ha, ca, ra = decode_png(png_a)
    wb, hb, cb, rb = decode_png(png_b)
    x0, y0, x1, y1 = box
    total = n = 0
    for y in range(y0, min(y1, ha, hb), step):
        la, lb = ra[y], rb[y]
        for x in range(x0, min(x1, wa, wb), step):
            for k in range(3):
                total += abs(la[x * ca + k] - lb[x * cb + k])
            n += 3
    return total / max(n, 1)
