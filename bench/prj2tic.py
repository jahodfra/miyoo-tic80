"""Convert a TIC-80 text project (.lua .moon .yue .js .wren .nut .py .scm .fnl, or .wasmp + .wasm)
into a binary .tic cart that the libretro core can load.

usage: python3 -I prj2tic.py <project> <out.tic> [--binary file.wasm]

Port of TIC-80's src/studio/project.c (loader) + src/cart.c (saver), bank 0 data only.
"""
import struct
import sys

COMMENT = {"lua": "--", "moon": "--", "yue": "--", "wasmp": "--", "fnl": ";;", "scm": ";;",
           "js": "//", "wren": "//", "nut": "//", "py": "#"}

# section tag -> (chunk type, nibble flip)   (project.c BinarySections / cart.c ChunkType)
SECTIONS = {"TILES": (1, True), "SPRITES": (2, True), "MAP": (4, True), "FLAGS": (6, True),
            "SFX": (9, True), "WAVES": (10, True), "PALETTE": (12, False), "TRACKS": (14, True),
            "PATTERNS": (15, True), "SCREEN": (18, True)}
CHUNK_CODE, CHUNK_BINARY = 5, 19
BANK = 1 << 16


def hex2bytes(h, flip):
    out = bytearray()
    for i in range(0, len(h) - 1, 2):
        a, b = h[i], h[i + 1]
        out.append(int(b + a if flip else a + b, 16))
    return bytes(out)


def chunk(ctype, data, bank=0):
    size = len(data)
    assert size <= BANK, (ctype, size)
    return struct.pack("<BHB", ctype | (bank << 5), size & 0xFFFF, 0) + data


def banked(ctype, data):
    """Code/binary > 64K is split; the FIRST 64K goes into the HIGHEST bank (cart.c)."""
    parts = [data[i:i + BANK] for i in range(0, max(len(data), 1), BANK)]
    out = b""
    for i, part in enumerate(parts):
        out += chunk(ctype, part, len(parts) - 1 - i)
    return out


def convert(path, binary=None):
    ext = path.rsplit(".", 1)[-1].lower()
    c = COMMENT[ext]
    text = open(path, encoding="utf-8").read().replace("\r", "")

    cut = text.find("\n%s <" % c)
    code = text if cut < 0 else text[:cut]
    out = b""

    for tag, (ctype, flip) in SECTIONS.items():
        start = text.find("%s <%s>" % (c, tag))
        if start < 0:
            continue
        end = text.find("\n%s </%s>" % (c, tag), start)
        rows = {}
        for line in text[start:end].split("\n")[1:]:
            line = line.strip()
            if not line.startswith(c):
                continue
            body = line[len(c):].strip()            # "001:abcd..."
            idx, _, hexdata = body.partition(":")
            rows[int(idx)] = hex2bytes(hexdata.strip(), flip)
        if not rows:
            continue
        rowsize = len(next(iter(rows.values())))
        buf = bytearray(rowsize * (max(rows) + 1))
        for i, r in rows.items():
            buf[i * rowsize:i * rowsize + len(r)] = r
        out += chunk(ctype, bytes(buf.rstrip(b"\0")) or b"\0")

    if binary:
        out += banked(CHUNK_BINARY, open(binary, "rb").read())
    out += banked(CHUNK_CODE, code.encode("utf-8"))
    return out


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) < 2:
        sys.exit(__doc__)
    binfile = a[a.index("--binary") + 1] if "--binary" in a else None
    data = convert(a[0], binfile)
    open(a[1], "wb").write(data)
    print(f"{a[1]}: {len(data)} bytes")
