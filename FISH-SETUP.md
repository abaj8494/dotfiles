# Fish Shell Setup

The `fish` directory currently has permission issues (owned by root).

To fix and stow fish:

```bash
cd ~/dotfiles
sudo chown -R $(whoami):staff fish/
mkdir -p fish/.config
mv fish fish-temp
mkdir fish
mv fish-temp fish/.config/fish
stow fish
```

Or simply run:
```bash
sudo chown -R $(whoami):staff ~/dotfiles/fish/
```

Then the fish package will be ready to stow like the others.
