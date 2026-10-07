#!/bin/zsh
# daily-comic.sh — mail one comic image per day, at a random time of day.
#
# Driven by the com.aayushbajaj.daily-comic LaunchAgent, which ticks every 60s.
# Each tick is a cheap no-op unless today's randomly-planned send time has arrived.
# Sends through msmtp (same path Emacs uses), so account selection + the gpg'd
# app password come from ~/.msmtprc.
#
#   daily-comic.sh            tick (what launchd runs)
#   daily-comic.sh --status   show plan, sent count, remaining images
#   daily-comic.sh --test     send one image to yourself now; touches no state
#   daily-comic.sh --now      send today's image right now (recorded as today's)
#
# Recipient lives OUTSIDE the repo (this repo is public):
#   ~/.config/daily-comic/config     TO=someone@example.com
#                                    BCC="me@example.com"   (optional, space-separated)
#
# State (~/.local/state/daily-comic/):
#   plan       "<YYYY-MM-DD> <epoch>"  — today's chosen send time
#   sent.log   "<YYYY-MM-DD>\t<file>\t<emoji>" per delivered mail; an image is
#              never repeated, and when the folder is exhausted the job goes quiet.

set -u
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8   # launchd gives no locale; the body is an emoji
export PATH=/opt/homebrew/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

FROM_ADDR="aayushbajaj7@gmail.com"
FROM_NAME="Aayush Bajaj"
SUBJECT="one of those days"
IMG_DIR="$HOME/lattice/3-resources/media/archive-gdrive/comics/one of those days"
MSMTP=/opt/local/bin/msmtp

CONF="$HOME/.config/daily-comic/config"
STATE="$HOME/.local/state/daily-comic"
PLAN="$STATE/plan"
SENT="$STATE/sent.log"
LOG="$HOME/Library/Logs/daily-comic.log"

MISSED_GRACE=1800    # planned time slept through by more than this → re-roll
RETRY_DELAY=1800     # after a failed send, don't hammer (a dead gpg cache means a pinentry popup per try)

EMOJI=(🦒 🌻 🌙 ✨ 🫶 🍓 🐝 🌈 🍋 🐥 🌼 🧸 🍯 🪐 🌸 🐌 🍄 🦋 ☁️ 🫧 🐳 🍉 🌞 🦦 🥐 🎈 🪴 🐢 🍒 🌷 🦔)

mkdir -p "$STATE"
touch "$SENT"

log() { print -r -- "$(date '+%F %T') $*" >> "$LOG"; }

# uniform integer in [0, $1) from the kernel — zsh's $RANDOM is only 15 bits and
# a fresh shell per tick is exactly the case where its seeding is weakest
rand() { print $(( $(od -An -N4 -tu4 /dev/urandom) % $1 )); }

remaining_images() {
  local f
  for f in "$IMG_DIR"/*.(jpg|jpeg|png|gif)(N); do
    grep -qF -- $'\t'"${f:t}"$'\t' "$SENT" || print -r -- "$f"
  done
}

# plan_today <earliest-epoch>: pick uniformly between then and 23:59:59 today
plan_today() {
  local from=$1 end span
  end=$(date -j -f '%F %T' "$TODAY 23:59:59" +%s)
  span=$(( end - from ))
  (( span < 60 )) && span=60
  local at=$(( from + $(rand $span) ))
  print -r -- "$TODAY $at" > "$PLAN"
  log "planned $(date -r $at '+%F %T')"
}

# read_plan → sets PLAN_DAY / PLAN_AT (empty when there is no plan file)
read_plan() {
  PLAN_DAY= PLAN_AT=
  [[ -s $PLAN ]] && read -r PLAN_DAY PLAN_AT < "$PLAN"
}

# send <image> <to> → 0 on delivery
send() {
  local img=$1 to=$2 emoji=$3 n=$4 boundary ext mime
  boundary="=_comic_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  ext=${img:e:l}
  case $ext in
    jpg|jpeg) mime=image/jpeg ;;
    *)        mime=image/$ext ;;
  esac
  {
    print -r -- "From: $FROM_NAME <$FROM_ADDR>"
    print -r -- "To: $to"
    print -r -- "Subject: $SUBJECT"
    print -r -- "Date: $(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')"
    print -r -- "Message-ID: <$(date +%s).$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')@${FROM_ADDR#*@}>"
    print -r -- "MIME-Version: 1.0"
    print -r -- "Content-Type: multipart/mixed; boundary=\"$boundary\""
    print
    print -r -- "--$boundary"
    print -r -- "Content-Type: text/plain; charset=UTF-8"
    print -r -- "Content-Transfer-Encoding: 8bit"
    print
    print -r -- "$emoji"
    print
    print -r -- "--$boundary"
    print -r -- "Content-Type: $mime; name=\"one-of-those-days-$n.$ext\""
    print -r -- "Content-Transfer-Encoding: base64"
    print -r -- "Content-Disposition: inline; filename=\"one-of-those-days-$n.$ext\""
    print
    base64 -b 76 -i "$img"
    print
    print -r -- "--$boundary--"
  } | "$MSMTP" -a gmail -f "$FROM_ADDR" -- "$to" ${=BCC:-}   # envelope-only, so no Bcc: header to leak
}

# pick + send + (optionally) record. $1 = recipient, $2 = record? (1/0)
deliver() {
  local to=$1 record=$2 imgs img emoji n
  imgs=("${(@f)$(remaining_images)}")
  if [[ -z ${imgs[1]:-} ]]; then
    log "no unsent images left in $IMG_DIR — nothing to do"
    return 2
  fi
  img=${imgs[$(( $(rand ${#imgs}) + 1 ))]}
  emoji=${EMOJI[$(( $(rand ${#EMOJI}) + 1 ))]}
  n=$(( $(wc -l < "$SENT") + 1 ))
  local rc=0
  send "$img" "$to" "$emoji" "$n" || rc=$?
  if (( rc == 0 )); then
    (( record )) && print -r -- "$TODAY"$'\t'"${img:t}"$'\t'"$emoji" >> "$SENT"
    log "sent ${img:t} $emoji → $to${BCC:+ (bcc $BCC)}$( (( record )) || print ' (test, not recorded)')"
    return 0
  fi
  log "SEND FAILED for ${img:t} (msmtp exit $rc) — see ~/.cache/msmtp.log"
  return 1
}

TODAY=$(date +%F)
NOW=$(date +%s)

case ${1:-} in
  --status)
    print "sent:      $(wc -l < "$SENT" | tr -d ' ')"
    print "remaining: $(remaining_images | wc -l | tr -d ' ')"
    if grep -q "^$TODAY"$'\t' "$SENT"; then print "today:     already sent"
    elif read_plan; [[ $PLAN_DAY == $TODAY ]]; then
      print "today:     planned for $(date -r $PLAN_AT '+%T')"
    else print "today:     not planned yet (next tick will)"; fi
    exit 0 ;;
  --test)
    deliver "$FROM_ADDR" 0; exit $? ;;
esac

[[ -r $CONF ]] && source "$CONF"
if [[ -z ${TO:-} ]]; then
  log "no TO= in $CONF — refusing to send"
  exit 1
fi

if [[ ${1:-} == --now ]]; then
  grep -q "^$TODAY"$'\t' "$SENT" && { print "already sent today"; exit 0; }
  deliver "$TO" 1; exit $?
fi

# ---- tick ----
grep -q "^$TODAY"$'\t' "$SENT" && exit 0                 # today's is out
[[ -z "$(remaining_images)" ]] && exit 0                 # folder exhausted

read_plan
if [[ $PLAN_DAY != $TODAY ]]; then
  plan_today $NOW
  read_plan
fi
AT=$PLAN_AT

(( NOW < AT )) && exit 0

# Slept through the slot: sending on wake would clump every mail at lid-open, so
# re-roll inside what's left of the day — unless there's too little day left.
END=$(date -j -f '%F %T' "$TODAY 23:59:59" +%s)
if (( NOW - AT > MISSED_GRACE && END - NOW > MISSED_GRACE )); then
  log "missed slot by $(( (NOW - AT) / 60 ))min — re-rolling"
  plan_today $NOW
  exit 0
fi

deliver "$TO" 1
rc=$?
if (( rc == 1 )); then
  print -r -- "$TODAY $(( NOW + RETRY_DELAY ))" > "$PLAN"
fi
exit 0
