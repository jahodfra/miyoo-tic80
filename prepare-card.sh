#!/usr/bin/env bash
# STEP 1 (PC): wipe an SD card, format it FAT32 and copy Onion OS onto it.
#
# usage: ./prepare-card.sh /dev/sdX [onion-tag]
#   ./prepare-card.sh /dev/sdc              -> latest Onion release
#   ./prepare-card.sh /dev/sdc v4.3.1-1
#
# !!! ERASES THE WHOLE DEVICE. Find the right one with: lsblk -o NAME,SIZE,MODEL,TRAN,LABEL
# Works without sudo (uses udisks, like the desktop's "Format" dialog).
set -euo pipefail

DEV="${1:?usage: $0 /dev/sdX [onion-tag]}"
TAG="${2:-latest}"
LABEL="MIYOO"
HERE="$(cd "$(dirname "$0")" && pwd)"
DL="$HERE/work/onion"; mkdir -p "$DL"

# ---- safety checks -------------------------------------------------------
[ -b "$DEV" ] || { echo "$DEV is not a block device"; exit 1; }
[ "$(lsblk -dno TYPE "$DEV")" = disk ] || { echo "$DEV must be a whole disk (e.g. /dev/sdc, not /dev/sdc1)"; exit 1; }
RM=$(lsblk -dno RM "$DEV" | tr -d ' '); TRAN=$(lsblk -dno TRAN "$DEV" | tr -d ' ')
if [ "$RM" != 1 ] && [ "$TRAN" != usb ] && [ "$TRAN" != mmc ]; then
  echo "$DEV is not removable/USB/MMC - refusing."; exit 1
fi
if lsblk -lno MOUNTPOINT "$DEV" | grep -qxE '/|/boot|/boot/efi|/home'; then
  echo "$DEV holds a system mount - refusing."; exit 1
fi
SIZE_GB=$(( $(lsblk -dbno SIZE "$DEV") / 1000000000 ))
[ "$SIZE_GB" -le 512 ] || { echo "$DEV is ${SIZE_GB} GB - too big for an SD card, refusing."; exit 1; }

echo "About to ERASE:"; lsblk -o NAME,SIZE,MODEL,TRAN,FSTYPE,LABEL,MOUNTPOINT "$DEV"
read -r -p "Type the device name ($(basename "$DEV")) to continue: " ans
[ "$ans" = "$(basename "$DEV")" ] || { echo "aborted"; exit 1; }

# ---- download Onion ------------------------------------------------------
if [ "$TAG" = latest ]; then
  TAG=$(curl -fsSL https://api.github.com/repos/OnionUI/Onion/releases/latest | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])')
fi
ZIP="$DL/Onion-$TAG.zip"
if [ ! -f "$ZIP" ]; then
  echo ">> downloading Onion $TAG"
  curl -fL -o "$ZIP.part" "https://github.com/OnionUI/Onion/releases/download/$TAG/Onion-$TAG.zip"
  mv "$ZIP.part" "$ZIP"
fi
unzip -tq "$ZIP"

# ---- partition + format (udisks, no sudo) ---------------------------------
echo ">> unmounting"
for p in $(lsblk -lno NAME "$DEV" | tail -n +2); do
  findmnt "/dev/$p" >/dev/null && udisksctl unmount -f -b "/dev/$p"
done
OBJ="/org/freedesktop/UDisks2/block_devices/$(basename "$DEV")"
echo ">> new MBR partition table + one FAT32 partition ($LABEL)"
gdbus call --system --dest org.freedesktop.UDisks2 --object-path "$OBJ" \
  --method org.freedesktop.UDisks2.Block.Format dos "{}" >/dev/null
gdbus call --system --dest org.freedesktop.UDisks2 --object-path "$OBJ" \
  --method org.freedesktop.UDisks2.PartitionTable.CreatePartitionAndFormat \
  1048576 0 "0x0c" "" "{}" vfat "{'label': <'$LABEL'>}" >/dev/null
sleep 2
PART="/dev/$(lsblk -lno NAME "$DEV" | sed -n 2p)"
lsblk -o NAME,SIZE,FSTYPE,FSVER,LABEL "$DEV"
[ "$(lsblk -no FSVER "$PART")" = FAT32 ] || { echo "format did not produce FAT32"; exit 1; }

# ---- copy Onion ----------------------------------------------------------
udisksctl mount -b "$PART" >/dev/null
MNT=$(findmnt -no TARGET "$PART")
echo ">> extracting Onion to $MNT"
unzip -q "$ZIP" -d "$MNT"
mkdir -p "$MNT/Roms/PICO" "$MNT/Roms/TIC/Imgs"
sync

# remount so the check reads from the card, not from the page cache
udisksctl unmount -b "$PART" >/dev/null; udisksctl mount -b "$PART" >/dev/null
MNT=$(findmnt -no TARGET "$PART")
echo ">> verifying every file against the zip (also catches fake/failing cards)"
python3 -I "$HERE/scripts/verify_zip.py" "$ZIP" "$MNT"

sync; udisksctl unmount -b "$PART" >/dev/null; udisksctl power-off -b "$DEV" || true
echo
echo "Card ready. Next: put it in the Miyoo and boot (first boot installs Onion, a few minutes)."
echo "Then: Apps -> Package Manager -> enable 'PICO-8 (Fake8)' and 'TIC-80', apply, power off."
echo "Then back on the PC: ./install-tic80.sh"
