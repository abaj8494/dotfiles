
export ZSH_DISABLE_COMPFIX=true
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

LFCD="$HOME/Google Drive/2. - code/206. - scripts/lfcd.sh"
if [ -f "$LFCD" ]; then
	source "$LFCD"
fi


# get power10k not to give output warning for fortune
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

#run fortune
fortune

# zsh variables
HISTFILE=~/.config/zsh/.zsh_history
HISTSIZE=999999999
SAVEHIST=999999999
setopt SHARE_HISTORY
setopt extended_glob
setopt cdablevars


# exports
export TERM=xterm-256color
# Path to your oh-my-zsh installation.
export ZSH="/Users/$USER/.oh-my-zsh"
# nvim as default editor
export EDITOR="/usr/local/bin/nvim"
# dbus for scli
export DBUS_LAUNCHD_SESSION_BUS_SOCKET="$HOME/Library/Caches/dbus/bus"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_LAUNCHD_SESSION_BUS_SOCKET"


## navigation
### exports are now in .zprofile



## path
### Created by `pipx` on 2021-10-23 02:37:28
export PATH="$PATH:/Users/aayushbajaj/.local/bin:/Users/aayushbajaj/.emacs.d/bin:/usr/local/go/bin/"
### .scripts folder
export PATH="$PATH:$HOME/.scripts/"
### go (the language)
export PATH="$PATH:$HOME/.go/bin"
export PATH="$PATH:$HOME/go/bin"
export PATH="$PATH:$HOME/Google Drive/2. - code/217. - moonlander/wally/build"
export GOPATH="/Users/aayushbajaj/go"



ZSH_THEME="powerlevel10k/powerlevel10k"


plugins=(
    z
    zsh-vi-mode
    macos
    copypath
    zsh-history-substring-search
    zsh-reload
    dirhistory
    # git
    copyfile
    zsh-autosuggestions
    zsh-syntax-highlighting
)

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/aayushbajaj/opt/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/aayushbajaj/opt/anaconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/aayushbajaj/opt/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/aayushbajaj/opt/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<


# aliases
# clear command
alias "cl=clear"
# cse to unsw ssh
alias cse="ssh -Y z5362216@weill.cse.unsw.edu.au"
alias rpi="ssh -X alarm@192.168.1.125"
# displayplacer awk command to reso
alias "reso=displayplacer list | awk 'END{print}'"
#alias pty="cd '$HOME/Google Drive/2. - code/212. - vimwiki/2022' && find . -type f -name 'week*.md' | sort | sed 's/.\{3\}$//' | xargs -I {} pandoc {}.md -o {}.pdf && pdfunite week*.pdf year.pdf && rm week*.pdf && cd -"


alias ZZ=exit
alias v=/usr/local/bin/nvim
alias vv="/usr/local/bin/nvim '$gcv/212.00 - cs/index.md'"
alias vvv="/usr/local/bin/nvim '$gcv/212.01 - pkm/index.md'"
alias vd="/usr/local/bin/nvim '$gcv/212.00 - cs/diary/diary.md'"
alias vvd="/usr/local/bin/nvim '$gcv/212.01 - pkm/diary/diary.md'"

alias tordl="'/Users/aayushbajaj/Google Drive/2. - code/297. - software/297.00 - git/cli-torrent-dl/tordl.sh'"
alias minidlnad="'/usr/local/opt/minidlna/sbin/minidlnad'"
alias aloc="locate -d $HOME/.local/var/db/locate.user.database"
alias sloc="locate -d /var/db/locate.database"

# music
alias npi="ncmpcpp -c ~/.config/ncmpcpp/config_rpi -b ~/.config/ncmpcpp/bindings"
alias nab="ncmpcpp -c ~/.config/ncmpcpp/config_abel -b ~/.config/ncmpcpp/bindings"

# configs
alias trc="v ~/.config/tmux/tmux.conf"
alias vrc="v ~/.config/nvim/init.lua"
alias zrc="v ~/.config/zsh/.zshrc"
alias lrc="v ~/.config/lf/lfrc"
alias krc="v ~/.config/karabiner/karabiner.json"
alias kirc="v ~/.config/kitty/kitty.conf"
alias mrc="v ~/.config/mutt/"
alias crc="v ~/.config/"

alias a="tmux a"
alias srs="drill-srs"
alias zhist="v ~/.config/zsh/.zsh_history"
alias mhist="v ~/.maple_history"

# custom functions

## delete the last x lines of file 
dtail () {
	tail -n $1 "$2" | wc -c | xargs -I {} truncate "$2" -s -{}
}

## start a countdown in minutes using the termdown utility
tt () {
	termdown $((60*$1))
}

## mc make and change into a directory
mc () {
	md "$@"
	cd "$@"
}




source $ZSH/oh-my-zsh.sh

# Generated for envman. Do not edit.
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"


# testing dotfiles script
source $HOME/.config/zsh/.zprofile

export PATH=$PATH:$HOME/.os161-toolchain/bin:/Library/Frameworks/Python.framework/Versions/2.7/bin
alias bmake="bmake -m ~/.os161-toolchain/share/mk"

source "$HOME/.local/servers/pgsql13/env"
alias p0="$PGHOME/bin/pg_ctl stop"
alias p1="$PGHOME/bin/pg_ctl -l $PGDATA/log start"
alias site="cd ~/website && hugo -v && rsync -vrP ~/website/public/ root@abaj.io:/var/www/abaj/"


source $HOME/.config/zsh/.zsecret


export "PATH=$PATH:/Users/aayushbajaj/Google Drive/2. - code/235. - sedawk/textual_apps/bin"
export PATH="/usr/local/opt/curl/bin:$PATH"
