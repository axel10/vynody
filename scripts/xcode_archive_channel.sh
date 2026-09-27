#!/bin/sh
# scripts/xcode_archive_channel.sh
# Ensure Rust / Cargo toolchain is accessible from Xcode's restricted build environment
if [ -d "$HOME/.cargo/bin" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi


is_archive=0
if [ "$ACTION" = "archive" ] || [ "$ACTION" = "install" ]; then
  is_archive=1
elif [ -n "$TARGET_BUILD_DIR" ] && [ "${TARGET_BUILD_DIR#*ArchiveIntermediates}" != "$TARGET_BUILD_DIR" ]; then
  is_archive=1
fi

if [ "$is_archive" -eq 1 ]; then
  is_channel_set=0
  if [ -n "$DART_DEFINES" ]; then
    OLD_IFS="$IFS"
    IFS=","
    for def in $DART_DEFINES; do
      decoded=$(echo "$def" | base64 -D 2>/dev/null || echo "$def" | base64 -d 2>/dev/null)
      case "$decoded" in
        CHANNEL=*|STORE_BUILD=*|APP_STORE_BUILD=*)
          is_channel_set=1
          echo "[Vynody Build] Distribution channel explicitly configured ($decoded), keeping as is."
          break
          ;;
      esac
    done
    IFS="$OLD_IFS"
  fi

  if [ "$is_channel_set" -eq 0 ]; then
    STORE_DEF=$(printf "CHANNEL=store" | base64)
    if [ -n "$DART_DEFINES" ]; then
      export DART_DEFINES="$DART_DEFINES,$STORE_DEF"
    else
      export DART_DEFINES="$STORE_DEF"
    fi
    echo "[Vynody Build] Xcode Archive build detected ($ACTION). Defaulting distribution channel to CHANNEL=store."
  fi
fi
