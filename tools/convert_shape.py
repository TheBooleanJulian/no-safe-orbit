"""Convert a Thomas small-body shape model to a TerrainMap height map.

    python tools/convert_shape.py m1phobos.tab data/phobos/phobos_shape.bin 11080
    python tools/convert_shape.py m2deimos.tab data/deimos/deimos_shape.bin 6200

Input: P. C. Thomas's shape models (PDS Small Bodies Node,
urn:nasa:pds:ast-sat.thomas.shape-models): one "latitude longitude radius"
row per grid point (degrees, km), planetocentric, every 2° (Phobos) or 5°
(Deimos), with both 0° and 360° written. Their longitudes run west: Stickney's
raised rim and floor fall at 30–55° in the table, and Stickney is at 49° W.

Output: the same format as data/moon/lola_elevation.bin (TerrainMap):
b"NSOLOLA1", width u16, height u16 (little-endian), then gzip of the
heights, whole metres relative to `mean_radius_m` as signed 16-bit, each
row delta-coded from 0. One pixel a degree (360 x 180), pixel centres at
east longitude -179.5 ... 179.5 and latitude 89.5 ... -89.5, sampled
bilinearly from the grid.
"""
import array, gzip, struct, sys

WIDTH, HEIGHT = 360, 180


def main(src, out, mean_radius_m):
    grid = {}
    lats, lons = set(), set()
    for line in open(src):
        parts = line.split()
        if len(parts) != 3:
            continue
        lat, lon, r = (float(x) for x in parts)
        grid[(lat, lon)] = r * 1000.0
        lats.add(lat)
        lons.add(lon)
    lat_step = sorted(lats)[1] - sorted(lats)[0]
    lon_step = sorted(lons)[1] - sorted(lons)[0]

    def radius(lat, lon_w):
        lon_w %= 360.0
        i = min(int((lat + 90.0) // lat_step), round(180.0 / lat_step) - 1)
        j = min(int(lon_w // lon_step), round(360.0 / lon_step) - 1)
        la0, lo0 = -90.0 + i * lat_step, j * lon_step
        ty, tx = (lat - la0) / lat_step, (lon_w - lo0) / lon_step
        a = grid[(la0, lo0)] * (1 - tx) + grid[(la0, lo0 + lon_step)] * tx
        b = grid[(la0 + lat_step, lo0)] * (1 - tx) + grid[(la0 + lat_step, lo0 + lon_step)] * tx
        return a * (1 - ty) + b * ty

    heights = array.array("h")
    lo, hi = 1e9, -1e9
    for y in range(HEIGHT):
        lat = 90.0 - (y + 0.5) * 180.0 / HEIGHT
        prev = 0
        for x in range(WIDTH):
            lon_e = -180.0 + (x + 0.5) * 360.0 / WIDTH
            h = round(radius(lat, -lon_e) - mean_radius_m)
            lo, hi = min(lo, h), max(hi, h)
            heights.append(h - prev)
            prev = h
    if sys.byteorder != "little":
        heights.byteswap()
    with open(out, "wb") as f:
        f.write(b"NSOLOLA1" + struct.pack("<HH", WIDTH, HEIGHT) + gzip.compress(heights.tobytes(), 9))
    print("%s: %d x %d, heights %d ... %d m about %.0f m" % (out, WIDTH, HEIGHT, lo, hi, mean_radius_m))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]))
