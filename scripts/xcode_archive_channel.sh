#!/bin/sh
# scripts/xcode_archive_channel.sh
# Ensure Rust / Cargo toolchain is accessible from Xcode's restricted build environment
if [ -d "$HOME/.cargo/bin" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi


# If building iOS target or performing an archive/install on any Apple platform, default to store channel
is_store_target=0
if [ "$PLATFORM_NAME" = "iphoneos" ] || [ "$PLATFORM_NAME" = "iphonesimulator" ]; then
  is_store_target=1
elif [ "$ACTION" = "archive" ] || [ "$ACTION" = "install" ]; then
  is_store_target=1
elif [ -n "$TARGET_BUILD_DIR" ] && [ "${TARGET_BUILD_DIR#*ArchiveIntermediates}" != "$TARGET_BUILD_DIR" ]; then
  is_store_target=1
fi

if [ "$is_store_target" -eq 1 ]; then
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
    echo "[Vynody Build] iOS/Archive build detected ($ACTION / $PLATFORM_NAME). Defaulting distribution channel to CHANNEL=store."
  fi
fi
