# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# get power10k not to give output warning for fortune
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

#run fortune
fortune

# zsh variables
HISTFILE=~/.zsh_history
HISTSIZE=99999
SAVEHIST=99999
setopt SHARE_HISTORY
setopt extended_glob
setopt cdablevars


# exports
export TERM=xterm-256color
# Created by `pipx` on 2021-10-23 02:37:28
export PATH="$PATH:/Users/aayushbajaj/.local/bin:/Users/aayushbajaj/.emacs.d/bin:/usr/local/go/bin/"
# Path to your oh-my-zsh installation.
export ZSH="/Users/$USER/.oh-my-zsh"
# nvim as default editor
export EDITOR="/usr/local/bin/nvim"

export gd="$HOME/Google Drive"
export gdc="$HOME/Google Drive/2. - code"
export gdm="$HOME/Google Drive/7. - media"


ZSH_THEME="powerlevel10k/powerlevel10k"


plugins=(
    z
    zsh-vi-mode
    macos
    copypath
    zsh-history-substring-search
    zsh-reload
    dirhistory
    git
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
alias "cse=ssh -X z5362216@cse.unsw.edu.au"
# displayplacer awk command to reso
alias "reso=displayplacer list | awk 'END{print}'"
# config for dotfiles
alias cfg='/usr/bin/git --git-dir=/Users/aayushbajaj/.cfg/ --work-tree=/Users/aayushbajaj'

alias ZZ=exit
alias v=/usr/local/bin/nvim

alias tordl="'/Users/aayushbajaj/Google Drive/8. - software/800. - git/cli-torrent-dl/tordl.sh'"

# custom functions
dtail () {
	tail -n $1 "$2" | wc -c | xargs -I {} truncate "$2" -s -{}
}
tt () {
	termdown $((60*$1))
}



source $ZSH/oh-my-zsh.sh



# Generated for envman. Do not edit.
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"

