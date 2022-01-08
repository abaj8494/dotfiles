# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi


# zsh variables
HISTFILE=~/.zsh_history
HISTSIZE=99999
SAVEHIST=99999
setopt SHARE_HISTORY
setopt extended_glob

# exports
export TERM=screen-256color
# Created by `pipx` on 2021-10-23 02:37:28
export PATH="$PATH:/Users/aayushbajaj/.local/bin"
# Path to your oh-my-zsh installation.
export ZSH="/Users/$USER/.oh-my-zsh"
# vim as default editor
export EDITOR="/usr/bin/vim"


ZSH_THEME="powerlevel10k/powerlevel10k"


plugins=(
    z
    zsh-vi-mode
    macos
    copydir
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
# xclip
alias "c=pbcopy"
alias "v=pbpaste"
alias "cc=xclip -selection clipboard"
alias "vv=xclip -o -selection clipboard"
# clear command
alias "cl=clear"
# cse to unsw ssh
alias "cse=ssh -X z5362216@cse.unsw.edu.au"
# displayplacer awk command to reso
alias "reso=displayplacer list | awk 'END{print}'"
# config for dotfiles
alias cfg='/usr/bin/git --git-dir=/Users/aayushbajaj/.cfg/ --work-tree=/Users/aayushbajaj'


# custom functions
dtail () {
	tail -n $1 "$2" | wc -c | xargs -I {} truncate "$2" -s -{}
}
tt () {
	termdown $((60*$1))
}

source $ZSH/oh-my-zsh.sh
alias ZZ=exit
