#!/usr/bin/env bash
# STEP 4 (PC, optional): download popular free PICO-8 and TIC-80 carts onto the card.
#
# usage: ./download-games.sh [card-mountpoint]     (default: the mounted card labelled MIYOO)
#
# PICO-8: the 20 most-liked featured carts on the Lexaloffle BBS (Nov 2026; PICOWARE skipped -
#         it is a multicart FAKE-08 can't chain-load). Saved as Roms/PICO/<name>.p8.png
# TIC-80: the top 20 of tic80.com "Games / top rated" (Nov 2026) + frantisek's carts.
#         Saved as Roms/TIC/<name>.tic, covers in Roms/TIC/Imgs (needs ImageMagick 'convert').
# Edit the lists below to change the selection. Existing files are skipped.
set -euo pipefail
UA="Mozilla/5.0"

PICO=(   # BBS thread id | file name
  "2145|Celeste" "30767|Just One Boss" "45334|Birds With Guns" "37236|PICOHOT"
  "44606|Terra - A Terraria Demake" "40099|High Stakes" "150620|PICO-BALL" "4051|The Lair"
  "49177|Ascent" "29709|Dank Tomb" "140564|Oblivion Eve" "54837|Marble Merger"
  "48032|Buns - Bunny Survivor" "37045|Porklike" "31864|Mai-Chan's Sweet Buns" "34188|FUZ"
  "2274|Dusk Child" "39471|Islander" "42252|Pico Zombie Garden" "3467|Combo Pool"
)
TIC=(    # tic80.com cart hash | file name
  "b88b74e7a6f923251de764d89d6f3507|8 Bit Panda" "d00e434d28ec464bf98aa96a4d53cefe|Stele"
  "4fb4348371246d26e9eb7f30e89a444d|Balmung" "51ebbe2af13164b2d47f2a2fe0a5a937|Mario Bros"
  "6e44e8213e39ffb32ec6163f9c595dec|Supernova" "13dacc4d8b359a393f9e87bc9b514f42|FPS80"
  "0550c042b230e937aa8466df95cce6dd|Super Meat Boy Demake" "62390344cba1e95a941bd5ad05562aff|Portal TIC-80"
  "edd382c230b67b29c728dbcb76422084|Turns of War" "74d69f265855b2a8c38ad45116bf48d7|Cauliflower Power"
  "739f92b6c28e237d408c3aa3fe28a521|Minetic" "8c2e54fc6e2205590f9330ab400e76ca|Bare Bones"
  "a41cd646e41f9ef1aebef1cc00b31a8c|Sonic Mini" "6be8b893b406f5178eb7509906f71f3e|Shadow Over the Twelve Lands"
  "1ed3e0341c2a8866aed873756a89e63d|Witchem Up" "7340ee6c22d80b2f7568c7dcf24991e2|Clay Pigeon"
  "3b836a6239a1ec5b1778750902dae8ef|WCQ No.6" "0316fed3441cd084bc8f11e9f815b487|Rebound 2 - Electric Boogaloo"
  "886e8d5aca2ff97cdbe9bcf0e92751d4|Beyond the Underground" "86883747bfcb2343936428c073bb01d5|Powder Game"
  # frantisek
  "82e6986c980fe75efa3e92957b52d068|Dragon Fury" "4ff45871aae3e9af443561934ff1b50e|Chiroptera"
  "a72dbde6d3acaf1d39846dc76c7a8f7a|Reorganize" "5d33f1584a17f708cce5c0d596bc4bd2|Rotating Earth"
)

M="${1:-}"
if [ -z "$M" ]; then
  PART=$(lsblk -lno NAME,LABEL | awk '$2=="MIYOO"{print "/dev/"$1; exit}')
  [ -n "$PART" ] || { echo "No card labelled MIYOO found - pass the mount point."; exit 1; }
  findmnt "$PART" >/dev/null || udisksctl mount -b "$PART" >/dev/null
  M=$(findmnt -no TARGET "$PART")
fi
mkdir -p "$M/Roms/PICO" "$M/Roms/TIC/Imgs"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CONVERT=$(command -v convert || command -v magick || true)

echo ">> PICO-8 -> $M/Roms/PICO"
for e in "${PICO[@]}"; do
  tid=${e%%|*}; name=${e#*|}; f="$M/Roms/PICO/$name.p8.png"
  [ -f "$f" ] && { echo "  skip  $name"; continue; }
  curl -fsSL -A "$UA" "https://www.lexaloffle.com/bbs/?tid=$tid" -o "$TMP/thread.html" || { echo "  FAIL  $name (thread)"; continue; }
  # the first cart in a thread is the one in the original post (later ones are from comments)
  url=$(grep -oE '/bbs/cposts/[^"`'"'"' ]+\.p8\.png' "$TMP/thread.html" | head -1 || true)
  [ -n "$url" ] && curl -fsSL -A "$UA" "https://www.lexaloffle.com$url" -o "$f" && echo "  ok    $name" || echo "  FAIL  $name"
  sleep 0.5
done

echo ">> TIC-80 -> $M/Roms/TIC"
for e in "${TIC[@]}"; do
  h=${e%%|*}; name=${e#*|}; f="$M/Roms/TIC/$name.tic"
  if [ -f "$f" ]; then echo "  skip  $name"; else
    curl -fsSL -A "$UA" "https://tic80.com/cart/$h/cart.tic" -o "$f" && echo "  ok    $name" || { rm -f "$f"; echo "  FAIL  $name"; }
  fi
  img="$M/Roms/TIC/Imgs/$name.png"
  if [ -n "$CONVERT" ] && [ ! -f "$img" ] && curl -fsSL -A "$UA" "https://tic80.com/cart/$h/cover.gif" -o "$TMP/c.gif"; then
    "$CONVERT" "$TMP/c.gif[0]" -filter point -resize 200% "$img" || true
  fi
done

# make Onion rebuild the game lists so new games appear
rm -f "$M/Roms/PICO/"*_cache*.db "$M/Roms/TIC/"*_cache*.db
sync
echo "done."
