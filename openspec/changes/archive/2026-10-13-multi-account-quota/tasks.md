## 1. Groundwork

- [x] 1.1 In the isolated test tmux server, confirm that `#{pane_id}` and `#{@opt}` inside a `#()` command are expanded before the job runs. For example, set `status-format[0]` to `#(echo #{pane_id} > $DIR/out)`, attach a client with `tmux -C` to force a redraw, and read `$DIR/out`. Record the outcome in design.md if it differs.
- [x] 1.2 Add a `tests/stub/tmux-recorder` helper (used only by the menu tests) that appends its arguments to a file. Verify that a dummy call records its args.

## 2. Reporter (quota-reporting)

- [x] 2.1 Generalise account naming in `bin/claude-tmux-status` per "Account Selection" (personal, `.claude-<name>`, other basenames, sanitising). Add checks for the personal/empty/`$HOME/.claude` cases and the `/opt/agents/.claude-client a` → `client-a` case. Verify that `tests/run.sh` passes, including the existing work check.
- [x] 2.2 Add pane attribution: find the nearest `claude` ancestor via `ps` (8 hops max, falling back to `$PPID`), and write `panes/<n>` atomically when `TMUX_PANE` is set. Add checks for "Claude in a tmux pane" (use a stub process named `claude` as the ancestor), "Outside tmux", and "API-key session still attributes its pane".
- [x] 2.3 Prune attribution files whose PID is not running. Add a check for "Dead attribution pruned" (seed `panes/9` with a PID from a finished subshell).

## 3. Badge (quota-badge)

- [x] 3.1 Parse `[pane] [pin] [auto]` and implement Account Resolution: pinned default `personal`, auto on unless `off`, and a pane file whose PID is alive and whose account state is valid. Treat an unexpanded literal `#{...}` argument as absent. Update the "work account not displayed" check to the new GIVEN (nothing pinned, no pane), add "Pinned account has not reported", and add checks for each Account Resolution scenario (use `$$` as a live PID).
- [x] 3.2 Read appearance with one `tmux show-options -gq` call (defaults when it fails), implement the five presets, custom `#RRGGBB,#RRGGBB`, the malformed→orange fallback, and the icon override. Add checks for "Preset scheme", "Custom scheme", "Malformed scheme", "Custom icon" and "Alarm overrides a custom scheme" against the isolated tmux server.
- [x] 3.3 Implement Inverted Style (base `#0B0D0F`, fill = channel/4 shadow, text = effective fill), used only when the detected account differs from the pin. Add checks for "Default scheme inverted" (`#3C2300`) and "Alarm inverted" (`#3A150E`), plus one asserting that the separator's fg matches the first run in the inverted style.
- [x] 3.4 Update the header comment in `bin/tmux-claude-widget` to document the new arguments and options. Verify that all existing badge checks still pass unchanged with two arguments.

## 4. Menu (quota-account-menu)

- [x] 4.1 Create `bin/tmux-claude-menu`: list the accounts from the state files (personal first, then alphabetical, skipping `*.tmp`), mark the current pin with `* `, and add `Unpin` and the `Auto-detect: on|off` toggle. Each action runs `set -g`/`set -gu` and then `refresh-client -S`. Show the disabled "No account has reported yet" item when the list is empty. Add checks with the tmux recorder for "Two accounts reported", "Nothing reported", "Pin the work account", "Unpin" and "Turn auto-detection off".
- [x] 4.2 Make the menu executable and verify that `./install.sh` symlinks it into `~/.local/bin` in a throwaway `$HOME`.

## 5. Configuration and docs

- [x] 5.1 Update `tmux/claude-tmux.conf`: both widget calls pass `'#{pane_id}' '#{@claude-quota-pin}' '#{@claude-quota-auto}'`, add `bind-key Q run-shell '~/.local/bin/tmux-claude-menu'`, and add commented examples for `@claude-quota-scheme-<account>` and `@claude-quota-icon-<account>`. Add a check that greps the conf for the "Shipped configuration" scenario.
- [x] 5.2 Update `README.md`: the multi-account behaviour, the options table (pin, auto, scheme, icon), the presets, the menu key, and the pinned vs inverted styles. Verify that every option name in the README matches the specs.

## 7. Background sessions

- [x] 7.1 Reporter: extract `session_id` from the payload, write `sessions/<id>` = `<account> <pid>` atomically (with or without `TMUX_PANE` and `rate_limits`), and prune session files whose PID is dead. Add checks for "Background session" and "Dead session pruned".
- [x] 7.2 Badge: accept `[pane_pid]` and, when no pane file applies, resolve a child `claude attach <id>` against `sessions/` (unique prefix, live PID). Add checks for "Pane attached to a background session" and "Attached session never reported", using a stub process whose arguments are `claude attach <id>`.
- [x] 7.3 Pass `'#{pane_pid}'` in both widget calls of `tmux/claude-tmux.conf` and update the "Shipped configuration" check to require the four formats.

## 6. End-to-end

- [x] 6.1 Run `tests/run.sh` and confirm that every check passes and that each new spec scenario has a check.
- [x] 6.2 Manual check in a real tmux: open a `claude` pane on `~/.claude-work` next to a personal one and a plain shell. Switch between them and confirm that the badge flips between inverted `work` and the pinned style. Then pin `work` via `prefix + Q` and confirm that the work pane renders un-inverted.
