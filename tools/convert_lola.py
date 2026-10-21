"""Convert NASA's LOLA lunar elevation map to data/moon/lola_elevation.bin.

Source: NASA SVS 4720 "CGI Moon Kit", ldem_16_uint.tif — 5760 x 2880
(16 pixels/degree), unsigned 16-bit, half-metres above a 1727.4 km radius,
equirectangular, top edge 90 N, left edge 180 W (as data/moon's colour map).

Output (read by scripts/presentation/lunar_terrain.gd):
    b"NSOLOLA1", width u16, height u16 (little-endian), then gzip of the
    heights as int16 metres relative to the 1737.4 km mean radius, each row
    stored as differences from the sample to its left (smooth terrain
    compresses far better that way).

Usage (stdlib only):
    curl -LO https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/ldem_16_uint.tif
    python tools/convert_lola.py ldem_16_uint.tif data/moon/lola_elevation.bin 2
The last argument is the downsampling factor (2: 8 pixels/degree).
"""
import array, gzip, struct, sys


def read_tiff_u16(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"II*\x00":
        raise SystemExit("expected a little-endian TIFF")
    ifd = struct.unpack_from("<I", data, 4)[0]
    count = struct.unpack_from("<H", data, ifd)[0]
    sizes = {3: 2, 4: 4}
    tags = {}
    for k in range(count):
        tag, typ, n, value = struct.unpack_from("<HHII", data, ifd + 2 + 12 * k)
        if tag not in (256, 257, 258, 259, 273, 277, 279) or typ not in sizes:
            continue  # only the layout tags, as SHORT or LONG
        size = sizes[typ]
        if n * size <= 4:
            raw = struct.unpack_from("<" + ("H" if typ == 3 else "I") * n, data, ifd + 2 + 12 * k + 8)
        else:
            raw = struct.unpack_from("<" + ("H" if typ == 3 else "I") * n, data, value)
        tags[tag] = list(raw)
    width, height = tags[256][0], tags[257][0]
    if tags.get(258, [16])[0] != 16 or tags.get(259, [1])[0] != 1 or tags.get(277, [1])[0] != 1:
        raise SystemExit("expected one uncompressed 16-bit channel")
    pixels = array.array("H")
    for off, n in zip(tags[273], tags[279]):
        pixels.frombytes(data[off:off + n])
    if sys.byteorder != "little":
        pixels.byteswap()
    if len(pixels) != width * height:
        raise SystemExit("strip data doesn't match %d x %d" % (width, height))
    return width, height, pixels


def main():
    src, dst, factor = sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 2
    width, height, px = read_tiff_u16(src)
    w, h = width // factor, height // factor
    out = array.array("h", bytes(2 * w * h))
    area = factor * factor
    lo, hi = 1 << 30, -(1 << 30)
    for y in range(h):
        rows = [px[(y * factor + dy) * width:(y * factor + dy + 1) * width] for dy in range(factor)]
        prev = 0
        for x in range(w):
            total = 0
            for r in rows:
                total += sum(r[x * factor:(x + 1) * factor])
            # Half-metres above 1727.4 km -> metres relative to 1737.4 km.
            metres = round(total / area * 0.5 - 10000.0)
            lo, hi = min(lo, metres), max(hi, metres)
            out[y * w + x] = max(-32768, min(32767, metres - prev))
            prev = metres
    if sys.byteorder != "little":
        out.byteswap()
    packed = gzip.compress(out.tobytes(), 9)
    with open(dst, "wb") as f:
        f.write(b"NSOLOLA1" + struct.pack("<HH", w, h) + packed)
    print("%s: %d x %d (%d px/deg), %d .. %d m, %.2f MB" % (dst, w, h, w // 360, lo, hi, (len(packed) + 12) / 1e6))


main()
