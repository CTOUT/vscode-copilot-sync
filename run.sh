#!/usr/bin/env sh
# ==============================================================================
# Cross-Platform POSIX Bootstrap Wrapper for VSCode-Copilot-Sync
#
# Provides a shell-native entrypoint for macOS, Linux, and WSL environments.
# Detects PowerShell 7+ (pwsh) and executes the appropriate script transparently.
# ==============================================================================

set -e

# Detect pwsh (PowerShell 7+)
if ! command -v pwsh >/dev/null 2>&1; then
    printf "\033[31m[ERROR] PowerShell (pwsh) 7+ is required but was not found on PATH.\033[0m\n\n" >&2
    printf "To install PowerShell:\n" >&2
    printf "  - macOS (Homebrew):  brew install --cask powershell\n" >&2
    printf "  - Ubuntu / Debian:   sudo apt-get update && sudo apt-get install -y powershell\n" >&2
    printf "  - RHEL / Fedora:     sudo dnf install -y powershell\n" >&2
    printf "  - Arch Linux (AUR):  yay -S powershell-bin\n" >&2
    printf "  - Official docs:     https://github.com/PowerShell/PowerShell\n\n" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Subcommand dispatch
COMMAND="repo"
if [ $# -gt 0 ]; then
    case "$1" in
        repo|init-repo)
            COMMAND="repo"
            shift
            ;;
        user|init-user)
            COMMAND="user"
            shift
            ;;
        update|update-repo)
            COMMAND="update-repo"
            shift
            ;;
        update-user)
            COMMAND="update-user"
            shift
            ;;
        sync)
            COMMAND="sync"
            shift
            ;;
        configure)
            COMMAND="configure"
            shift
            ;;
        -*)
            # Options passed directly; default to repo command
            COMMAND="repo"
            ;;
        help|-h|--help)
            printf "VSCode-Copilot-Sync POSIX Wrapper\n\n"
            printf "Usage:\n"
            printf "  ./run.sh [command] [options...]\n\n"
            printf "Commands:\n"
            printf "  repo         Initialize Copilot resources in target repository (default)\n"
            printf "  user         Initialize global user-level Copilot resources\n"
            printf "  update       Update repository-level subscribed resources\n"
            printf "  update-user  Update user-level subscribed resources\n"
            printf "  sync         Sync awesome-copilot upstream cache\n"
            printf "  configure    Run initial configuration wizard\n\n"
            printf "Examples:\n"
            printf "  ./run.sh -DryRun\n"
            printf "  ./run.sh user -DryRun\n"
            printf "  ./run.sh sync\n"
            printf "  ./run.sh update\n"
            exit 0
            ;;
        *)
            # Unknown command; pass directly to init-repo.ps1
            COMMAND="repo"
            ;;
    esac
fi

case "$COMMAND" in
    repo)
        exec pwsh -NoProfile -File "$SCRIPT_DIR/scripts/init-repo.ps1" "$@"
        ;;
    user)
        exec pwsh -NoProfile -File "$SCRIPT_DIR/scripts/init-user.ps1" "$@"
        ;;
    update-repo)
        exec pwsh -NoProfile -File "$SCRIPT_DIR/scripts/update-repo.ps1" "$@"
        ;;
    update-user)
        exec pwsh -NoProfile -File "$SCRIPT_DIR/scripts/update-user.ps1" "$@"
        ;;
    sync)
        exec pwsh -NoProfile -File "$SCRIPT_DIR/scripts/sync-awesome-copilot.ps1" "$@"
        ;;
    configure)
        exec pwsh -NoProfile -File "$SCRIPT_DIR/configure.ps1" "$@"
        ;;
esac
