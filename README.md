# Dotfiles

My personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Structure

Each directory represents a "package" that can be independently stowed. Files are organized as they would appear from `~`:

```
dotfiles/
├── emacs/
│   └── .emacs.d/          # → ~/.emacs.d/
├── nvim/
│   └── .config/
│       └── nvim/          # → ~/.config/nvim/
├── zsh/
│   ├── .zshrc            # → ~/.zshrc
│   └── .zprofile         # → ~/.zprofile
├── kitty/
│   └── .config/
│       └── kitty/         # → ~/.config/kitty/
└── ... (other packages)
```

## Installation

### Prerequisites

```bash
# Install GNU Stow
brew install stow
```

### Setup

1. Clone this repository:
```bash
git clone git@github.com:abaj8494/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

2. Initialize submodules (for tmux plugins):
```bash
git submodule update --init --recursive
```

3. Stow the packages you want:
```bash
# Stow individual packages
stow emacs
stow nvim
stow zsh
stow kitty
stow alacritty
stow tmux
stow aerospace
stow karabiner

# Or stow everything at once
stow */
```

## Usage

### Stowing a Package

From the `~/dotfiles` directory:

```bash
stow <package-name>
```

This creates symlinks from `~` to the files in `~/dotfiles/<package-name>/`.

### Unstowing a Package

```bash
stow -D <package-name>
```

This removes the symlinks created by stow.

### Restowing a Package

If you've made changes and want to refresh the symlinks:

```bash
stow -R <package-name>
```

### Adopting Existing Files

If you have existing config files that aren't yet in your dotfiles:

```bash
stow --adopt <package-name>
```

This will move the existing files into your dotfiles repo and create symlinks.

## Packages

- **emacs**: Emacs configuration with custom elisp modules
- **nvim**: Neovim configuration with Lua
- **zsh**: Zsh shell configuration
- **kitty**: Kitty terminal emulator
- **alacritty**: Alacritty terminal emulator
- **tmux**: Tmux configuration with plugins
- **aerospace**: AeroSpace window manager
- **karabiner**: Karabiner-Elements keyboard customization
- **lf**: lf file manager
- **htop**: htop system monitor
- **neofetch**: Neofetch system info
- **gh**: GitHub CLI
- **zathura**: Zathura PDF viewer
- **xournalpp**: Xournal++ note-taking
- **rstudio**: RStudio preferences
- **bettertouchtool**: BetterTouchTool presets
- **iterm2**: iTerm2 configuration
- **pistol**: Pistol file previewer
- **ctpv**: ctpv file previewer
- **stpv**: stpv file previewer

## Notes

- The `.stow-local-ignore` file tells stow which files to ignore (git files, README, etc.)
- Stow works by creating symlinks, so any changes you make to the files in `~` will be reflected in the git repo
- Remember to commit and push your changes regularly!
- Some packages (like `fish`) may have permission issues - fix with `sudo chown -R $(whoami):staff <package>/`

## Tips

- Always run stow commands from the `~/dotfiles` directory
- Use `stow -n -v <package>` to do a dry run and see what would happen
- If you get conflicts, you can use `stow --adopt` to pull existing files into your repo
- Keep sensitive files (like `.zsh_history`, `.z`) in `.gitignore`

## Git Workflow

```bash
cd ~/dotfiles

# Check status
git status

# Add changes
git add .

# Commit
git commit -m "Update configs"

# Push to remote
git push origin macos
```
