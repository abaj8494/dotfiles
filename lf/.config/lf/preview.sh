#!/bin/sh
# lf previewer — kali. Args: $1=path $2=width $3=height $4=x $5=y
f="$1"
case "$(file -Lb --mime-type -- "$f")" in
    text/* | application/json | application/javascript | application/xml | */xml)
        batcat --color=always --style=numbers --paging=never --terminal-width "${2:-80}" -- "$f" 2>/dev/null \
            || cat -- "$f" ;;
    inode/directory)
        eza -la --icons=auto --group-directories-first -- "$f" 2>/dev/null || ls -la -- "$f" ;;
    application/pdf)
        command -v pdftotext >/dev/null 2>&1 && pdftotext -l 5 -- "$f" - 2>/dev/null || { file -Lb -- "$f"; } ;;
    image/*)
        file -Lb -- "$f"; echo; eza -l --no-user --color=always -- "$f" 2>/dev/null ;;
    *)
        file -Lb -- "$f"; echo; eza -la --icons=auto -- "$f" 2>/dev/null || ls -la -- "$f" ;;
esac
