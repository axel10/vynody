#!/bin/bash
if [ -z "$LASTFM_SECRET" ]; then
    extract_env() {
        key="$1"
        file="$2"
        if [ -f "$file" ]; then
            grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d '=' -f 2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" | tr -d '\r\n'
        fi
    }
    if [ -f ".env" ]; then
        LASTFM_SECRET=$(extract_env "LASTFM_SECRET" ".env")
    fi
    if [ -z "$LASTFM_SECRET" ] && [ -f ".env.local" ]; then
        LASTFM_SECRET=$(extract_env "LASTFM_SECRET" ".env.local")
    fi
fi

flutter run --dart-define=LASTFM_SECRET="$LASTFM_SECRET" --profile "$@"
