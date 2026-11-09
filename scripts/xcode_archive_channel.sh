#!/bin/sh
# scripts/xcode_archive_channel.sh
# Ensure Rust / Cargo toolchain is accessible from Xcode's restricted build environment
if [ -d "$HOME/.cargo/bin" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

# Locate project root directory
ROOT_DIR=""
if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR/.." ]; then
  ROOT_DIR="$(cd "$PROJECT_DIR/.." 2>/dev/null && pwd)"
fi
if [ -z "$ROOT_DIR" ]; then
  ROOT_DIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
fi

extract_env() {
  key="$1"
  file="$2"
  if [ -f "$file" ]; then
    grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d '=' -f 2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" | tr -d '\r\n'
  fi
}

# 1. If building iOS target or performing an archive/install on any Apple platform, default to store channel
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
    STORE_DEF=$(printf "CHANNEL=store" | base64 | tr -d '\r\n')
    if [ -n "$DART_DEFINES" ]; then
      export DART_DEFINES="$DART_DEFINES,$STORE_DEF"
    else
      export DART_DEFINES="$STORE_DEF"
    fi
    echo "[Vynody Build] iOS/Archive build detected ($ACTION / $PLATFORM_NAME). Defaulting distribution channel to CHANNEL=store."
  fi
fi

# 2. Inject LASTFM_SECRET if not already present in DART_DEFINES
is_lastfm_set=0
if [ -n "$DART_DEFINES" ]; then
  OLD_IFS="$IFS"
  IFS=","
  for def in $DART_DEFINES; do
    decoded=$(echo "$def" | base64 -D 2>/dev/null || echo "$def" | base64 -d 2>/dev/null)
    case "$decoded" in
      LASTFM_SECRET=*)
        is_lastfm_set=1
        echo "[Vynody Build] LASTFM_SECRET already present in DART_DEFINES, keeping as is."
        break
        ;;
    esac
  done
  IFS="$OLD_IFS"
fi

if [ "$is_lastfm_set" -eq 0 ]; then
  secret="$LASTFM_SECRET"
  if [ -z "$secret" ] && [ -n "$ROOT_DIR" ]; then
    if [ -f "$ROOT_DIR/.env" ]; then
      secret=$(extract_env "LASTFM_SECRET" "$ROOT_DIR/.env")
    fi
    if [ -z "$secret" ] && [ -f "$ROOT_DIR/.env.local" ]; then
      secret=$(extract_env "LASTFM_SECRET" "$ROOT_DIR/.env.local")
    fi
  fi

  # Fallback: probe login shell in case Xcode was launched as macOS GUI app without shell env
  if [ -z "$secret" ] && [ "$(uname)" = "Darwin" ]; then
    secret=$(zsh -lc 'echo "$LASTFM_SECRET"' 2>/dev/null | tr -d '\r\n')
  fi

  if [ -n "$secret" ]; then
    LASTFM_DEF=$(printf "LASTFM_SECRET=%s" "$secret" | base64 | tr -d '\r\n')
    if [ -n "$DART_DEFINES" ]; then
      export DART_DEFINES="$DART_DEFINES,$LASTFM_DEF"
    else
      export DART_DEFINES="$LASTFM_DEF"
    fi
    echo "[Vynody Build] Injected LASTFM_SECRET into DART_DEFINES."
  else
    echo "[Vynody Build] Warning: LASTFM_SECRET not found in env, .env, or login shell. Last.fm scrobbling will be disabled."
  fi
fi
