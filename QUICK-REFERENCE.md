# GNU Stow Quick Reference

## Common Commands

```bash
# From ~/dotfiles directory

# Stow a package (create symlinks)
stow nvim

# Unstow a package (remove symlinks)
stow -D nvim

# Restow a package (refresh symlinks)
stow -R nvim

# Dry run (see what would happen)
stow -n -v nvim

# Adopt existing files into repo
stow --adopt nvim

# Stow all packages
stow */
```

## How Stow Works

Stow creates symlinks from your home directory to files in the package:

```
~/dotfiles/nvim/.config/nvim/init.lua
                ↓ stow creates symlink
~/.config/nvim/init.lua → ~/dotfiles/nvim/.config/nvim/init.lua
```

## Package Structure

Each package mirrors the structure from `~`:

```
nvim/                    # Package name
└── .config/            # Mirrors ~/.config/
    └── nvim/           # Mirrors ~/.config/nvim/
        └── init.lua    # Your actual file
```

## Daily Workflow

1. Edit files normally (they're symlinked)
2. Changes are automatically in git repo
3. Commit and push:

```bash
cd ~/dotfiles
git add .
git commit -m "Update config"
git push
```

## Helper Script

```bash
cd ~/dotfiles
./manage-dotfiles.sh list      # List packages
./manage-dotfiles.sh stow nvim # Stow a package
./manage-dotfiles.sh status    # Git status
```

## New Machine Setup

```bash
git clone git@github.com:abaj8494/dotfiles.git ~/dotfiles
cd ~/dotfiles
git submodule update --init --recursive
stow */  # or stow individual packages
```

## Your Packages

- **emacs** - Emacs config (→ ~/.emacs.d/)
- **nvim** - Neovim config (→ ~/.config/nvim/)
- **zsh** - Zsh config (→ ~/.zshrc, ~/.zprofile)
- **kitty** - Kitty terminal (→ ~/.config/kitty/)
- **alacritty** - Alacritty terminal (→ ~/.config/alacritty/)
- **tmux** - Tmux config (→ ~/.config/tmux/)
- **aerospace** - Window manager (→ ~/.config/aerospace/)
- **karabiner** - Keyboard customization (→ ~/.config/karabiner/)
- Plus 12 more packages!

## Troubleshooting

**Conflict error?**
```bash
# Option 1: Remove the conflicting file
rm ~/.config/nvim/init.lua
stow nvim

# Option 2: Adopt it into your repo
stow --adopt nvim
```

**Want to see what stow will do?**
```bash
stow -n -v nvim  # Dry run with verbose output
```

**Accidentally stowed wrong thing?**
```bash
stow -D package-name  # Unstow it
```
