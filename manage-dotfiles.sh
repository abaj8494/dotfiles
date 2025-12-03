#!/bin/bash

# Dotfiles management script

DOTFILES_DIR="$HOME/dotfiles"

show_help() {
    cat << EOF
Dotfiles Management Script

Usage: ./manage-dotfiles.sh [command] [package]

Commands:
    stow <package>      - Stow a package (create symlinks)
    unstow <package>    - Unstow a package (remove symlinks)
    restow <package>    - Restow a package (refresh symlinks)
    adopt <package>     - Adopt existing files into dotfiles
    list                - List all available packages
    status              - Show git status
    sync                - Pull latest changes and restow all
    help                - Show this help message

Examples:
    ./manage-dotfiles.sh stow nvim
    ./manage-dotfiles.sh list
    ./manage-dotfiles.sh status
EOF
}

list_packages() {
    echo "Available packages:"
    cd "$DOTFILES_DIR"
    for dir in */; do
        pkg="${dir%/}"
        if [ -d "$pkg/.config" ] || [ -d "$pkg/.emacs.d" ] || [ -f "$pkg/.zshrc" ]; then
            echo "  - $pkg"
        fi
    done
}

case "$1" in
    stow)
        if [ -z "$2" ]; then
            echo "Error: Please specify a package"
            exit 1
        fi
        cd "$DOTFILES_DIR"
        stow -v "$2"
        ;;
    unstow)
        if [ -z "$2" ]; then
            echo "Error: Please specify a package"
            exit 1
        fi
        cd "$DOTFILES_DIR"
        stow -D -v "$2"
        ;;
    restow)
        if [ -z "$2" ]; then
            echo "Error: Please specify a package"
            exit 1
        fi
        cd "$DOTFILES_DIR"
        stow -R -v "$2"
        ;;
    adopt)
        if [ -z "$2" ]; then
            echo "Error: Please specify a package"
            exit 1
        fi
        cd "$DOTFILES_DIR"
        stow --adopt -v "$2"
        ;;
    list)
        list_packages
        ;;
    status)
        cd "$DOTFILES_DIR"
        git status
        ;;
    sync)
        cd "$DOTFILES_DIR"
        echo "Pulling latest changes..."
        git pull
        echo "Restowing all packages..."
        stow -R */
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
