#!/bin/zsh

# Builds BarKit and installs it into /Applications (override with INSTALL_DIR).
# Usage: Scripts/install.sh [--no-launch]

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
app_path="$project_root/build/Release/BarKit.app"
install_dir="${INSTALL_DIR:-/Applications}"
installed_path="$install_dir/BarKit.app"
launch=1

for arg in "$@"; do
    case "$arg" in
        --no-launch) launch=0 ;;
        *)
            printf 'Unknown option: %s\n' "$arg" >&2
            exit 1
            ;;
    esac
done

"$script_dir/build.sh"

if [[ ! -d "$app_path" ]]; then
    printf 'Build output not found: %s\n' "$app_path" >&2
    exit 1
fi

mkdir -p "$install_dir"

if pgrep -x BarKit >/dev/null 2>&1; then
    printf 'Quitting running BarKit...\n'
    osascript -e 'tell application id "com.barkit.app" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -x BarKit >/dev/null 2>&1 || break
        sleep 0.25
    done
    pkill -x BarKit >/dev/null 2>&1 || true
fi

printf 'Installing to %s...\n' "$installed_path"
rm -rf "$installed_path"
ditto "$app_path" "$installed_path"

printf 'Installed: %s\n' "$installed_path"

if (( launch )); then
    open "$installed_path"
    printf 'Launched BarKit.\n'
fi
