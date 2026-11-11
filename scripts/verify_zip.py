"""Check that every file of a zip was written correctly to a directory (CRC32 compare).
usage: python3 -I verify_zip.py <archive.zip> <dest-dir>"""
import os
import sys
import zipfile
import zlib

z = zipfile.ZipFile(sys.argv[1])
root = sys.argv[2]
bad = n = 0
for i in z.infolist():
    if i.is_dir():
        continue
    n += 1
    p = os.path.join(root, i.filename)
    c = 0
    try:
        with open(p, "rb") as f:
            while (b := f.read(1 << 20)):
                c = zlib.crc32(b, c)
    except OSError as e:
        print("ERR", p, e)
        bad += 1
        continue
    if c != i.CRC:
        print("MISMATCH", p)
        bad += 1
print(f"{n} files checked, {bad} bad")
sys.exit(1 if bad else 0)
