#!/usr/bin/env bash
# Regenerates docs/img/*.png: the badges are the real tmux-claude-widget output,
# fed mocked state files, a pinned clock and stubbed tmux options; the bar around
# them and the menu are mock-ups. Needs Google Chrome (headless), ImageMagick,
# python3 and a Nerd Font Mono (JetBrainsMonoNL by default, see tmux2html.py).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$ROOT/docs/screenshots
OUT=$ROOT/docs/img
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

export HOME=$WORK/home TZ=UTC LC_ALL=en_US.UTF-8 FAKE_NOW=1800000000   # Fri 2027-01-15 08:00 UTC
NOW=$FAKE_NOW
D=$HOME/.cache/claude-tmux
mkdir -p "$D/panes" "$WORK/stub" "$OUT"
cp "$ROOT/tests/stub/date" "$WORK/stub/"
# The widget reads per-account looks from `tmux show-options -g`; answer from $OPTS.
cat > "$WORK/stub/tmux" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = show-options ] && printf '%s\n' "${OPTS:-}"
exit 0
EOF
chmod +x "$WORK/stub/tmux"
export PATH=$WORK/stub:$PATH

BRIEFCASE=$'\U000F00D6'   # nf-md-briefcase
OPTS='@claude-quota-scheme-orange orange
@claude-quota-scheme-yellow yellow
@claude-quota-scheme-green green
@claude-quota-scheme-cyan cyan
@claude-quota-scheme-pink pink
@claude-quota-scheme-custom "#C6B6FF,#9580FF"
@claude-quota-icon-icon '"$BRIEFCASE"
export OPTS

H=3600 DAY=86400
# state <account> <5h used> <5h resets in (s)> <week used> <week resets in (s)>
# A 5h used of -1 is an account without a 5h window; a negative "resets in" is past.
state() {
  local f=$D/quota; [ "$1" = personal ] || f=$D/quota-$1
  local r5=$((NOW + $3)); (($2 < 0)) && r5=0
  echo "$2 $r5 $4 $((NOW + $5)) $NOW" > "$f"
}
# w <variant> <account> [inverted] [sepbg]: one badge. Inverted = the account is
# detected in the active pane while another one is pinned.
w() {
  if [ -n "${3:-}" ]; then
    echo "$2 $$" > "$D/panes/1"
    "$ROOT/bin/tmux-claude-widget" "$1" "${4:-default}" %1 nobody on
  else
    "$ROOT/bin/tmux-claude-widget" "$1" "${4:-default}" '' "$2" off
  fi
}
pair() { printf '%s\t%s' "$(w session "$@")" "$(w week "$@")"; }
row() { local cap=$1; shift; printf 'row\t%s\t%s\n' "$cap" "$(pair "$@")"; }

shoot() {  # shoot <name>, spec on stdin
  python3 "$HERE/tmux2html.py" > "$WORK/$1.html"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$WORK/chrome" --force-device-scale-factor=2 \
    --window-size=1700,1000 --screenshot="$WORK/$1.png" "file://$WORK/$1.html" 2>/dev/null
  magick "$WORK/$1.png" -trim +repage -bordercolor '#1E1F29' -border 32 "$OUT/$1.png"
  echo "$OUT/$1.png"
}

# ── Hero: the two-row bar as it sits under tmux2k ──────────────────────────
state personal 42 $((2 * H + 13 * 60)) 61 $((4 * DAY + 6 * H))
# Glyphs by codepoint, so an editor or font can't silently drop them.
R=$'\uE0B0' L=$'\uE0B2' BRANCH=$'\uE0A0' FOLDER=$'\uF07B' CPU=$'\uF4BC' CLK=$'\U000F0954'
win="#[fg=#7970A9] 1 zsh  #[fg=#0B0D0F,bg=#9580FF] 2 claude #[default]#[fg=#7970A9]  3 logs "
left2="#[fg=#0B0D0F,bg=#9580FF] $BRANCH main #[fg=#9580FF,bg=#1E1F29]$R"
right2="#[fg=#FF80BF,bg=#1E1F29]$L#[fg=#0B0D0F,bg=#FF80BF] $FOLDER ~/code #[fg=#FFFF80,bg=#FF80BF]$L#[fg=#0B0D0F,bg=#FFFF80] $CPU 23% #[fg=#80FFEA,bg=#FFFF80]$L#[fg=#0B0D0F,bg=#80FFEA] $CLK 08:00 "
{
  printf 'bar\t%s\t%s\n' "$win" "$(w session personal '' '#1E1F29')"
  printf 'bar\t%s\t%s\n' "$left2" "$right2$(w week personal '' '#80FFEA')"
} | shoot bar

# ── States ─────────────────────────────────────────────────────────────────
for n in 0 15 40 65 75; do state "g$n" "$n" $((4 * H + 30 * 60)) "$n" $((3 * DAY))
done
state alarm 93 $((25 * 60)) 85 $((DAY + 3 * H))
state ultra -1 0 37 $((5 * DAY + 6 * H))
state rolled 88 -60 79 -60
{
  printf 'title\tThe gauge fills left to right with usage\n'
  for n in 0 15 40 65 75; do row "$n%" "g$n"; done
  printf 'title\tAlarm: session ≥ 90%%, week ≥ 80%% (overrides any scheme)\n'
  row "alarm" alarm
  printf 'title\tWindow reset since the last report: back to 0%%, reset unknown\n'
  row "rolled over" rolled
  printf 'title\tAccount with only the weekly window (verified Ultra)\n'
  row "weekly only" ultra
} | shoot states

# ── Accounts: schemes, pinned vs detected, icons ───────────────────────────
i=0
for a in orange yellow green cyan pink custom icon; do
  state "$a" $((18 + i * 9)) $((H + i * 1700)) $((52 - i * 5)) $((DAY + i * 70000))
  i=$((i + 1))
done
{
  printf 'title\tColour schemes: pinned account | detected in the active pane (inverted)\n'
  for a in orange yellow green cyan pink; do
    printf 'row\t%s\t%s\t%s\n' "$a" "$(pair "$a")" "$(pair "$a" inverted)"
  done
  printf 'row\t%s\t%s\t%s\n' '"#C6B6FF,#9580FF"' "$(pair custom)" "$(pair custom inverted)"
  printf 'title\tCustom icon (@claude-quota-icon-<account>)\n'
  printf 'row\t%s\t%s\t%s\n' "icon (briefcase)" "$(pair icon)" "$(pair icon inverted)"
  printf 'title\tAlarm, detected\n'
  printf 'row\t%s\t%s\n' "alarm" "$(pair alarm inverted)"
} | shoot accounts

# ── The prefix + Q menu (mock-up) and Claude Code's own status line ────────
payload=$(jq -nc --arg d "$HOME/code/homelab" '{model:{display_name:"Opus"},workspace:{current_dir:$d},
  context_window:{used_percentage:23,total_input_tokens:58000,total_output_tokens:436,context_window_size:1000000},
  cost:{total_cost_usd:1.23},rate_limits:{five_hour:{used_percentage:42,resets_at:1},seven_day:{used_percentage:61,resets_at:1}}}')
line=$(printf '%s' "$payload" | CLAUDE_CONFIG_DIR= "$ROOT/bin/claude-tmux-status")
{
  printf 'title\tprefix + Q\n'
  printf 'html\t%s\n' '<div class="menu"><div class="t">Claude quota</div><div class="sel">* personal</div><div>  work</div><div>  club</div><hr><div>  Unpin             (u)</div><div>  Auto-detect: on   (a)</div></div>'
  printf 'title\tInside Claude Code (the statusLine command'"'"'s own line)\n'
  printf 'text\t\t%s\n' "$line"
} | shoot menu
