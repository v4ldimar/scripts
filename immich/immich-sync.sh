#!/bin/bash

SOURCE="/srv/storage/hdd-01/photos/upload"
DEST="/srv/storage/hdd-01/media/immich-library-clean"

echo "Building Immich clean library (stable copy mode)..."

mkdir -p "$DEST"

# clean old structure
rm -rf "$DEST"/*

find "$SOURCE" -type f | while read file; do

  # skip metadata files
  if [[ "$file" == *.xmp ]]; then
    continue
  fi

  YEAR=$(date -r "$file" +"%Y")

  TARGET_DIR="$DEST/$YEAR"
  mkdir -p "$TARGET_DIR"

  FILE=$(basename "$file")

  cp "$file" "$TARGET_DIR/$FILE"

done

done

echo "Done."
