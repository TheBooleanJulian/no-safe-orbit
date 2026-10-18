"""Convert the Yale Bright Star Catalogue (CDS V/50 catalog.gz) to data/stars/bright_stars.txt.

Usage (stdlib only):
    curl -LO https://cdsarc.cds.unistra.fr/ftp/V/50/catalog.gz
    python tools/convert_bsc5.py catalog.gz data/stars/bright_stars.txt
"""
import gzip, sys
src, dst = sys.argv[1], sys.argv[2]
rows = []
with gzip.open(src, "rt", encoding="ascii", errors="replace") as f:
    for line in f:
        line = line.rstrip("\n").ljust(115)
        ra_h, ra_m, ra_s = line[75:77], line[77:79], line[79:83]
        de_sign, de_d, de_m, de_s = line[83], line[84:86], line[86:88], line[88:90]
        vmag = line[102:107].strip()
        if not ra_h.strip() or not vmag:
            continue  # removed entries (novae, non-stellar) have no J2000 position
        ra = (int(ra_h) + int(ra_m) / 60 + float(ra_s) / 3600) * 15.0
        dec = int(de_d) + int(de_m) / 60 + int(de_s) / 3600
        if de_sign == "-":
            dec = -dec
        bv = line[109:114].strip()
        rows.append((int(line[0:4]), ra, dec, float(vmag), float(bv) if bv else 0.65))
with open(dst, "w", encoding="ascii", newline="\n") as out:
    out.write("# Yale Bright Star Catalogue, 5th rev. (Hoffleit & Warren 1991), CDS catalogue V/50.\n")
    out.write("# Converted by tools/convert_bsc5.py: J2000 positions. Columns: HR, RA (deg), Dec (deg), V mag, B-V (0.65 if unknown).\n")
    for hr, ra, dec, v, bv in rows:
        out.write("%d %.5f %.5f %.2f %.2f\n" % (hr, ra, dec, v, bv))
print("stars:", len(rows), "brightest:", sorted(rows, key=lambda r: r[3])[:3])
for hr in (2491, 424, 7001):  # Sirius, Polaris, Vega
    print([r for r in rows if r[0] == hr])
