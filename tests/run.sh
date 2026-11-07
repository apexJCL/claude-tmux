#!/usr/bin/env bash
# Checks each openspec scenario against bin/. No dependencies beyond bash, jq and
# tmux. Every case runs in a throwaway $HOME, with "now" pinned by tests/stub/date.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$ROOT/bin
export PATH=$ROOT/tests/stub:$PATH TZ=UTC LC_ALL=en_US.UTF-8
unset TMUX TMUX_PANE   # running the suite from inside tmux must not leak the real pane
# A private socket dir, so the badge never reads options from the user's own tmux.
export TMUX_TMPDIR; TMUX_TMPDIR=$(mktemp -d)
NOW=1800000000
# Glyphs, by codepoint so an editor or font can't silently drop them.
ICON=$'\uEC82' LOGO=$'\U000F0674' CLOCK=$'\U000F0954' CALENDAR=$'\U000F00ED' SEP=$'\uE0B2'
pass=0 fail=0

check() {  # check <name> <condition-exit-status>
  if [ "$2" -eq 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi
}

fresh_home() { HOME=$(mktemp -d); export HOME; mkdir -p "$HOME/.cache/claude-tmux"; }
state() { echo "$*" > "$HOME/.cache/claude-tmux/quota"; }
widget() { FAKE_NOW=$NOW "$BIN/tmux-claude-widget" "$@"; }
plain() { sed 's/#\[[^]]*\]//g'; }   # strip tmux style directives

# ── quota-reporting ────────────────────────────────────────────────────────
payload='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"HOMEDIR/proj"},
  "context_window":{"used_percentage":23.4,"total_input_tokens":58000,"total_output_tokens":436,"context_window_size":1240000},
  "cost":{"total_cost_usd":1.234},
  "rate_limits":{"five_hour":{"used_percentage":41.7,"resets_at":1000},"seven_day":{"used_percentage":12.2,"resets_at":2000}}}'
report() { printf '%s' "${payload//HOMEDIR/$HOME}" | FAKE_NOW=$NOW "$BIN/claude-tmux-status"; }

fresh_home
out=$(CLAUDE_CONFIG_DIR= report)
[ "$(cat "$HOME/.cache/claude-tmux/quota")" = "41 1000 12 2000 $NOW" ]; check "reporting: state line" $?
[ "$out" = "$ICON [personal] Opus · ~/proj · 23% (58k/1.2M) · \$1.23" ]; check "reporting: status line" $?
[ ! -e "$HOME/.cache/claude-tmux/quota.tmp" ]; check "reporting: no tmp left behind" $?

fresh_home
out=$(CLAUDE_CONFIG_DIR=$HOME/.claude-work report)
[ -s "$HOME/.cache/claude-tmux/quota-work" ] && [ ! -e "$HOME/.cache/claude-tmux/quota" ]; check "reporting: work file" $?
[[ $out == "$ICON [work] "* ]]; check "reporting: work label" $?

fresh_home; state "5 1 6 2 3"
echo '{"cwd":"/x","model":{"display_name":"Opus"}}' | CLAUDE_CONFIG_DIR= "$BIN/claude-tmux-status" >/dev/null
[ "$(cat "$HOME/.cache/claude-tmux/quota")" = "5 1 6 2 3" ]; check "reporting: no rate_limits keeps state" $?

fresh_home
printf '%s' "$(jq -c 'del(.rate_limits.five_hour)' <<< "${payload//HOMEDIR/$HOME}")" | CLAUDE_CONFIG_DIR= FAKE_NOW=$NOW "$BIN/claude-tmux-status" >/dev/null
[ "$(cat "$HOME/.cache/claude-tmux/quota")" = "-1 0 12 2000 $NOW" ]; check "reporting: weekly-only account" $?

fresh_home; state "5 1 6 2 3"
printf '%s' "$(jq -c 'del(.rate_limits.seven_day)' <<< "${payload//HOMEDIR/$HOME}")" | CLAUDE_CONFIG_DIR= FAKE_NOW=$NOW "$BIN/claude-tmux-status" >/dev/null
[ "$(cat "$HOME/.cache/claude-tmux/quota")" = "5 1 6 2 3" ]; check "reporting: no weekly window keeps state" $?

fresh_home; state "5 1 6 2 3"
echo 'not json' | CLAUDE_CONFIG_DIR= FAKE_NOW=$NOW "$BIN/claude-tmux-status" >/dev/null 2>&1
[ "$(tr -s ' ' < "$HOME/.cache/claude-tmux/quota")" = " $NOW" ]; check "reporting: known gap, bad payload clobbers state" $?

fresh_home; state "5 1 6 2 3"
echo '{"model":{"display_name":"Opus"}}' | CLAUDE_CONFIG_DIR= FAKE_NOW=$NOW "$BIN/claude-tmux-status" >/dev/null
[ "$(cat "$HOME/.cache/claude-tmux/quota")" = "0 -1 0  $NOW" ]; check "reporting: known gap, missing dir shifts fields" $?

for cfg in unset '' HOMEDIR/.claude; do
  fresh_home
  if [ "$cfg" = unset ]; then out=$(unset CLAUDE_CONFIG_DIR; report); else out=$(CLAUDE_CONFIG_DIR=${cfg//HOMEDIR/$HOME} report); fi
  [ -s "$HOME/.cache/claude-tmux/quota" ] && [[ $out == "$ICON [personal] "* ]]; check "reporting: personal account (${cfg:-empty})" $?
done

fresh_home
out=$(CLAUDE_CONFIG_DIR='/opt/agents/.claude-client a' report)
[ -s "$HOME/.cache/claude-tmux/quota-client-a" ] && [[ $out == "$ICON [client-a] "* ]]; check "reporting: other config dir" $?

# Pane attribution. A symlink named claude stands in for the Claude process (ps
# reports the name it was run as; a bare copy of bash is killed by code signing),
# with a shell in between, as Claude runs the statusLine command through one.
PANES=.cache/claude-tmux/panes
fresh_home
ln -s "$(command -v bash)" "$HOME/claude"
TMUX_PANE=%7 CLAUDE_CONFIG_DIR=$HOME/.claude-work "$HOME/claude" -c \
  'echo $$ > "$HOME/claude.pid"; printf %s "$1" | bash -c "\"\$0\"; true" "$2" >/dev/null; true' _ "${payload//HOMEDIR/$HOME}" "$BIN/claude-tmux-status"
[ "$(cat "$HOME/$PANES/7" 2>/dev/null)" = "work $(cat "$HOME/claude.pid")" ]; check "reporting: claude in a tmux pane" $?

fresh_home
CLAUDE_CONFIG_DIR= report >/dev/null
[ -z "$(ls -A "$HOME/$PANES" 2>/dev/null)" ]; check "reporting: outside tmux" $?

fresh_home; state "5 1 6 2 3"
echo '{"cwd":"/x","model":{"display_name":"Opus"}}' | TMUX_PANE=%3 CLAUDE_CONFIG_DIR= "$BIN/claude-tmux-status" >/dev/null
[ -s "$HOME/$PANES/3" ] && [ "$(cat "$HOME/.cache/claude-tmux/quota")" = "5 1 6 2 3" ]; check "reporting: API-key session attributes its pane" $?

fresh_home; mkdir -p "$HOME/$PANES"
( : ) & dead=$!; wait $dead
echo "work $dead" > "$HOME/$PANES/9"; echo "work $$" > "$HOME/$PANES/8"
CLAUDE_CONFIG_DIR= report >/dev/null
[ ! -e "$HOME/$PANES/9" ]; check "reporting: dead attribution pruned" $?
[ -e "$HOME/$PANES/8" ]; check "reporting: live attribution kept" $?

# Session attribution: a background session reports outside any pane.
SESSIONS=.cache/claude-tmux/sessions SID=2d2bb59a-35a0-486e-829e-bf780556d8c8
fresh_home
ln -s "$(command -v bash)" "$HOME/claude"
FAKE_NOW=$NOW CLAUDE_CONFIG_DIR=$HOME/.claude-work "$HOME/claude" -c \
  'echo $$ > "$HOME/claude.pid"; printf %s "$1" | bash -c "\"\$0\"; true" "$2" >/dev/null; true' _ \
  "$(jq -c --arg s "$SID" '.session_id = $s' <<< "${payload//HOMEDIR/$HOME}")" "$BIN/claude-tmux-status"
[ "$(cat "$HOME/$SESSIONS/$SID" 2>/dev/null)" = "work $(cat "$HOME/claude.pid")" ]; check "reporting: background session" $?
[ -z "$(ls -A "$HOME/$PANES" 2>/dev/null)" ]; check "reporting: background session writes no pane file" $?
[ "$(cat "$HOME/.cache/claude-tmux/quota-work")" = "41 1000 12 2000 $NOW" ]; check "reporting: session id leaves the state line intact" $?

fresh_home
jq -c '.session_id = "a/b c"' <<< "${payload//HOMEDIR/$HOME}" | CLAUDE_CONFIG_DIR= FAKE_NOW=$NOW "$BIN/claude-tmux-status" >/dev/null
[ -f "$HOME/$SESSIONS/a-b-c" ]; check "reporting: session id sanitised" $?

fresh_home; mkdir -p "$HOME/$SESSIONS"
echo "work $dead" > "$HOME/$SESSIONS/abc"; echo "work $$" > "$HOME/$SESSIONS/def"
CLAUDE_CONFIG_DIR= report >/dev/null
[ ! -e "$HOME/$SESSIONS/abc" ] && [ -e "$HOME/$SESSIONS/def" ]; check "reporting: dead session pruned" $?

# ── quota-badge ────────────────────────────────────────────────────────────
fresh_home
[ -z "$(widget session)" ]; check "badge: no state prints nothing" $?
echo "1 9999999999 1 9999999999 $NOW" > "$HOME/.cache/claude-tmux/quota-work"
[ -z "$(widget session)" ]; check "badge: work account not displayed" $?

state "10 $((NOW + 100)) 10 $((NOW + 100)) $((NOW - 604801))"
[ -z "$(widget session)" ]; check "badge: stale report" $?
state "10 $((NOW + 100)) 10 $((NOW + 100)) $NOW"
[ -z "$(widget month)" ]; check "badge: unknown variant" $?
# No 5h window: session gauges the week and shows its reset time; week centres its %.
state "-1 0 26 $((NOW + 3600)) $NOW"   # NOW is 2027-01-15 08:00 UTC
[ "$(widget session | plain)" = "$SEP $LOGO $CALENDAR 01/15 09:00 " ]; check "badge: no 5h window, session shows week reset date-time" $?
[ "$(widget week | plain)" = "$SEP $LOGO     26%       " ]; check "badge: no 5h window, week centres the percentage" $?
regular=$(state "26 $((NOW + 3600)) 26 $((NOW + 3600)) $NOW"; widget week | plain)
state "-1 0 26 $((NOW + 3600)) $NOW"
[ "${#regular}" -eq "$(widget week | plain | wc -m | tr -d ' ')" ]; check "badge: no 5h window, week keeps its width" $?
state "-1 0 85 $((NOW + 3600)) $NOW"
[[ $(widget session) == *"#FF9580"* ]]; check "badge: no 5h window, session uses the weekly alarm" $?
state "-1 0 26 $((NOW - 1)) $NOW"
[ "$(widget session | plain)" = "$SEP $LOGO $CALENDAR --/-- --:-- " ]; check "badge: no 5h window, rolled-over week" $?

state "50 $((NOW + 2*3600 + 13*60)) 41 $(date -j -f %Y-%m-%d -u 2027-09-21 +%s 2>/dev/null || date -d 2027-09-21 +%s) $NOW"
[ "$(widget session | plain)" = "$SEP $LOGO 50% │ $CLOCK 02:13 " ]; check "badge: session label" $?
[ "$(widget week | plain)" = "$SEP $LOGO 41% │ $CALENDAR 09/21 " ]; check "badge: week label" $?
[[ $(widget session) == '#[fg=#F08C00,bg=#80FFEA]'* ]]; check "badge: default separator" $?
[[ $(widget session '#0B0D0F') == '#[fg=#F08C00,bg=#0B0D0F]'* ]]; check "badge: custom separator" $?
[[ $(widget session) == *'#[norange default]' ]]; check "badge: closes its range" $?
# 17-cell label at 50% -> round(8.5) = 9 filled cells
[[ $(widget session) == *"#[fg=#0B0D0F,bg=#F08C00] $LOGO 50% │ #[fg=#0B0D0F,bg=#FFCA80]"* ]]; check "badge: gauge split" $?

state "87 $((NOW - 1)) 10 $((NOW + 100)) $NOW"
[ "$(widget session | plain)" = "$SEP $LOGO 0% │ $CLOCK --:-- " ]; check "badge: rollover" $?
state "87 0 10 0 $NOW"
[ "$(widget session | plain)" = "$SEP $LOGO 87% │ $CLOCK --:-- " ]; check "badge: unknown reset keeps percentage" $?

state "89 $((NOW + 100)) 80 $((NOW + 100)) $NOW"
[[ $(widget session) == *FFCA80* && $(widget session) != *FF9580* ]]; check "badge: session 89 normal" $?
[[ $(widget week) == *FF9580* && $(widget week) == *E8553A* ]]; check "badge: week 80 alarm" $?
state "90 $((NOW + 100)) 79 $((NOW + 100)) $NOW"
[[ $(widget session) == *E8553A* ]]; check "badge: session 90 alarm" $?
[[ $(widget week) != *FF9580* ]]; check "badge: week 79 normal" $?

state "0 $((NOW + 100)) 100 $((NOW + 100)) $NOW"
[[ $(widget session) != *F08C00* ]]; check "badge: empty gauge" $?
[[ $(widget week) != *'bg=#FF9580]'* ]]; check "badge: full gauge" $?

# Account resolution. $$ is a live PID; $dead (above) is a finished one.
qwork() { echo "$*" > "$HOME/.cache/claude-tmux/quota-work"; }
pane() { mkdir -p "$HOME/$PANES"; echo "$2" > "$HOME/$PANES/$1"; }
pinned() { [[ $1 == *'#[fg=#0B0D0F,bg='* ]]; }
inverted() { [[ $1 == *'#[fg=#F08C00,bg=#0B0D0F]'* && $1 != *'#[fg=#0B0D0F,'* ]]; }
shows() { [[ $(plain <<< "$1") == *" $2% "* ]]; }

fresh_home; state "10 $((NOW + 100)) 10 $((NOW + 100)) $NOW"
[ -z "$(widget session '#80FFEA' '' work '')" ]; check "badge: pinned account has not reported" $?
qwork "60 $((NOW + 100)) 60 $((NOW + 100)) $NOW"
out=$(widget session); shows "$out" 10 && pinned "$out"; check "badge: no arguments beyond the variant" $?
pane 4 "work $$"
out=$(widget session '#80FFEA' %4 personal ''); shows "$out" 60 && inverted "$out"; check "badge: active pane runs another account" $?
out=$(widget session '#80FFEA' %4 work ''); shows "$out" 60 && pinned "$out"; check "badge: active pane runs the pinned account" $?
pane 5 "work $dead"
out=$(widget session '#80FFEA' %5 personal ''); shows "$out" 10 && pinned "$out"; check "badge: claude has exited in the pane" $?
out=$(widget session '#80FFEA' %4 personal off); shows "$out" 10 && pinned "$out"; check "badge: auto-detection off" $?
pane 6 "api $$"
out=$(widget session '#80FFEA' %6 personal ''); shows "$out" 10 && pinned "$out"; check "badge: detected account has no usable report" $?
out=$(widget session '#80FFEA' '#{pane_id}' '#{@claude-quota-pin}' '#{@claude-quota-auto}')
shows "$out" 10 && pinned "$out"; check "badge: unexpanded formats are ignored" $?

# Attached background session: a child of ours (the "pane process") named like
# `claude attach <id>`, and a session file under the full id.
session() { mkdir -p "$HOME/$SESSIONS"; echo "$2" > "$HOME/$SESSIONS/$1"; }
attach() { ( exec -a "claude attach $1" sleep 30 ) & attach_pid=$!; }
attach 2d2bb59a
session "$SID" "work $$"
out=$(widget session '#80FFEA' %9 personal '' $$); shows "$out" 60 && inverted "$out"; check "badge: pane attached to a background session" $?
out=$(widget session '#80FFEA' %9 personal off $$); shows "$out" 10 && pinned "$out"; check "badge: attached session, auto off" $?
session "$SID" "work $dead"
out=$(widget session '#80FFEA' %9 personal '' $$); shows "$out" 10 && pinned "$out"; check "badge: attached session has ended" $?
session "$SID" "work $$"; session 2d2bb59a-0000 "work $$"
out=$(widget session '#80FFEA' %9 personal '' $$); shows "$out" 10 && pinned "$out"; check "badge: ambiguous attach id" $?
kill $attach_pid; wait $attach_pid 2>/dev/null
attach 0000beef
out=$(widget session '#80FFEA' %9 personal '' $$); shows "$out" 10 && pinned "$out"; check "badge: attached session never reported" $?
kill $attach_pid; wait $attach_pid 2>/dev/null

# Inverted style: work detected in %4 while personal is pinned.
qwork "50 $((NOW + 100)) 50 $((NOW + 100)) $NOW"
out=$(widget session '#80FFEA' %4 personal '')
[[ $out == *'#[fg=#F08C00,bg=#3C2300]'* && $out == *'#[fg=#F08C00,bg=#0B0D0F]'* ]]; check "badge: default scheme inverted" $?
[[ $out == '#[fg=#3C2300,bg=#80FFEA]'* ]]; check "badge: inverted separator matches first run" $?
qwork "95 $((NOW + 100)) 50 $((NOW + 100)) $NOW"
[[ $(widget session '#80FFEA' %4 personal '') == *'#[fg=#E8553A,bg=#3A150E]'* ]]; check "badge: alarm inverted" $?

# Account appearance, read from a (private) tmux server.
tmux -f /dev/null new-session -d
work() { widget session '#80FFEA' '' work ''; }
qwork "50 $((NOW + 100)) 50 $((NOW + 100)) $NOW"
tmux set -g @claude-quota-scheme-work green
out=$(work); [[ $out == *'bg=#3CC832]'* && $out == *'bg=#8AFF80]'* ]]; check "badge: preset scheme" $?
tmux set -g @claude-quota-scheme-work '#AABBCC,#112233'
out=$(work); [[ $out == *'bg=#112233]'* && $out == *'bg=#AABBCC]'* ]]; check "badge: custom scheme" $?
tmux set -g @claude-quota-scheme-work teal
out=$(work); [[ $out == *'bg=#F08C00]'* && $out == *'bg=#FFCA80]'* ]]; check "badge: malformed scheme" $?
tmux set -g @claude-quota-icon-work $'\U000F0BBF'
[[ $(work | plain) == "$SEP "$'\U000F0BBF'" 50% "* ]]; check "badge: custom icon" $?
tmux set -g @claude-quota-scheme-work green
qwork "95 $((NOW + 100)) 50 $((NOW + 100)) $NOW"
out=$(work); [[ $out == *'bg=#E8553A]'* && $out == *'bg=#FF9580]'* && $out != *3CC832* ]]; check "badge: alarm overrides a custom scheme" $?
tmux kill-server

# ── quota-account-menu ─────────────────────────────────────────────────────
# tmux is the recorder here (a real menu needs an attached client); each item's
# command is then run against a private server to see what it sets.
menu() {
  rm -f "$HOME/rec"; mkdir -p "$HOME/opts" "$HOME/rbin"
  ln -sf "$ROOT/tests/stub/tmux-recorder" "$HOME/rbin/tmux"
  PATH=$HOME/rbin:$PATH TMUX_RECORD=$HOME/rec TMUX_RECORD_OPTS=$HOME/opts "$BIN/tmux-claude-menu"
}
# menu_cmd <label>: the command of the menu item labelled <label>.
menu_cmd() { awk -v l="$1" 'f == 2 { print; exit } f { f++ } $0 == l { f = 1 }' "$HOME/rec"; }
pins() { sed -n 's/^set -g @claude-quota-pin \([^ ]*\) ;.*/\1/p' "$HOME/rec" | xargs; }
run_item() { echo "$(menu_cmd "$1")" > "$HOME/item.conf"; tmux source-file "$HOME/item.conf" 2>/dev/null; }

fresh_home
echo 1 > "$HOME/.cache/claude-tmux/quota"; echo 1 > "$HOME/.cache/claude-tmux/quota-work"; echo 1 > "$HOME/.cache/claude-tmux/quota-work.tmp"
menu
[ "$(pins)" = "personal work" ] && grep -qx '\* personal' "$HOME/rec" && grep -qx work "$HOME/rec"; check "menu: two accounts reported" $?

fresh_home; menu
grep -qx -- '-No account has reported yet' "$HOME/rec" && [ -z "$(pins)" ]; check "menu: nothing reported" $?

fresh_home; echo 1 > "$HOME/.cache/claude-tmux/quota"; echo 1 > "$HOME/.cache/claude-tmux/quota-work"
mkdir -p "$HOME/opts"; echo work > "$HOME/opts/@claude-quota-pin"; menu
grep -qx '\* work' "$HOME/rec" && grep -qx personal "$HOME/rec"; check "menu: current pin marked" $?

tmux -f /dev/null new-session -d
fresh_home; echo 1 > "$HOME/.cache/claude-tmux/quota-work"; menu
run_item work
[ "$(tmux show -gqv @claude-quota-pin)" = work ] && [[ $(menu_cmd work) == *'; refresh-client -S' ]]; check "menu: pin the work account" $?
run_item Unpin
[ -z "$(tmux show -gqv @claude-quota-pin)" ]; check "menu: unpin" $?
run_item 'Auto-detect: on'
[ "$(tmux show -gqv @claude-quota-auto)" = off ]; check "menu: turn auto-detection off" $?
echo off > "$HOME/opts/@claude-quota-auto"; menu
run_item 'Auto-detect: off'
[ "$(tmux show -gqv @claude-quota-auto)" = on ]; check "menu: turn auto-detection back on" $?
tmux kill-server

fresh_home
"$ROOT/install.sh" "$HOME/.local/bin" >/dev/null
[ -L "$HOME/.local/bin/tmux-claude-menu" ] && [ -x "$HOME/.local/bin/tmux-claude-menu" ]; check "menu: installed" $?

CONF=$ROOT/tmux/claude-tmux.conf
calls=$(grep -v "^#" "$CONF" | grep -c "tmux-claude-widget ")
full=$(grep -v "^#" "$CONF" | grep "tmux-claude-widget " | grep -cF "'#{pane_id}' '#{@claude-quota-pin}' '#{@claude-quota-auto}' '#{pane_pid}')")
grep -q '^bind-key Q run-shell .*tmux-claude-menu' "$CONF" && ((calls == 2 && full == 2)); check "menu: shipped configuration" $?
# The conf must parse as a whole (tmux2k is absent, so status-right starts empty).
tmux -f /dev/null new-session -d && tmux source-file "$CONF" 2>/dev/null
[[ $(tmux show -gv status-right) == *"tmux-claude-widget week '#80FFEA' '#{pane_id}'"* ]]; check "conf: sources cleanly" $?
tmux kill-server

# ── two-row-status ─────────────────────────────────────────────────────────
tmux -f /dev/null new-session -d
pristine=$(tmux show -gv 'status-format[0]')
"$BIN/tmux-two-row-status"
row0=$(tmux show -gv 'status-format[0]'); row1=$(tmux show -gv 'status-format[1]')
[ "$(tmux show -gv status)" = 2 ]; check "two-row: status 2" $?
[[ $row0 == *'#{E:@status-top-right}'* ]]; check "two-row: top-right on row 0" $?
[[ $row1 == "${pristine%%'#[list=on align='*}"* ]]; check "two-row: row 1 starts with status-left" $?
"$BIN/tmux-two-row-status"
[ "$(tmux show -gv 'status-format[0]')" = "$row0" ] && [ "$(tmux show -gv 'status-format[1]')" = "$row1" ]; check "two-row: idempotent" $?
tmux kill-server

tmux -f /dev/null new-session -d
tmux set -g '@status-format-default' 'custom'
"$BIN/tmux-two-row-status"
[ "$(tmux show -gv status)" = on ] && [ "$(tmux show -gv 'status-format[0]')" = "$pristine" ]; check "two-row: unfamiliar default left alone" $?
tmux kill-server

echo "$pass passed, $fail failed"
((fail == 0))
