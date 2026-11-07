#!/usr/bin/env python3
"""Turn a spec of tmux format strings into an HTML page for a screenshot.

Spec lines on stdin, tab-separated:
  title <text>                       a section heading
  row   <caption> <fmt> [<fmt>...]   a caption and badges side by side
  bar   <left fmt> <right fmt>       a full-width status row, left and right aligned
  text  <caption> <plain text>       a line of plain terminal text
  html  <raw html>                   anything else (the menu mock)

Only the #[fg=..,bg=..] / default parts of tmux styles matter for badges; the
rest (norange, nolist, align, push-default) is ignored.
"""
import html
import re
import sys

BG = "#1E1F29"   # terminal / bar background ("default")
FG = "#F8F8F2"
FONT = "'JetBrainsMonoNL Nerd Font Mono', 'JetBrainsMono Nerd Font Mono', 'Symbols Nerd Font Mono', monospace"


def fmt2html(s: str) -> str:
    out, fg, bg = [], None, None
    for m in re.finditer(r"#\[([^\]]*)\]|([^#]+|#(?!\[))", s):
        if m.group(1) is not None:
            for d in re.split(r"[ ,]", m.group(1)):
                if d == "default":
                    fg = bg = None
                elif d.startswith("fg="):
                    fg = None if d[3:] == "default" else d[3:]
                elif d.startswith("bg="):
                    bg = None if d[3:] == "default" else d[3:]
        else:
            out.append(
                f'<span style="color:{fg or FG};background:{bg or "transparent"}">'
                f"{html.escape(m.group(2))}</span>"
            )
    return "".join(out)


body = []
for raw in sys.stdin.read().splitlines():
    if not raw.strip():
        continue
    kind, *f = raw.split("\t")
    if kind == "title":
        body.append(f'<h2>{html.escape(f[0])}</h2>')
    elif kind == "row":
        cells = "".join(f'<div class="b">{fmt2html(x)}</div>' for x in f[1:])
        body.append(f'<div class="row"><div class="cap">{html.escape(f[0])}</div>{cells}</div>')
    elif kind == "bar":
        body.append(f'<div class="bar"><div>{fmt2html(f[0])}</div><div>{fmt2html(f[1])}</div></div>')
    elif kind == "text":
        cap = f'<div class="cap">{html.escape(f[0])}</div>' if f[0] else ""
        body.append(f'<div class="row">{cap}<div class="b">{html.escape(f[1])}</div></div>')
    elif kind == "html":
        body.append(f[0])

print(f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  body {{ margin: 0; padding: 24px; background: {BG}; color: {FG};
         font-family: {FONT}; font-size: 22px; line-height: 1.25; width: max-content; }}
  .b, .bar div {{ white-space: pre; }}
  .row {{ display: flex; align-items: center; gap: 28px; margin: 10px 0; }}
  .cap {{ width: 21ch; color: #7970A9; font-size: 18px; }}
  .bar {{ display: flex; justify-content: space-between; width: 118ch; background: {BG}; }}
  h2 {{ font-size: 18px; color: #9580FF; font-weight: normal; margin: 22px 0 6px; }}
  h2:first-child {{ margin-top: 0; }}
  .menu {{ display: inline-block; border: 1px solid {FG}; padding: 2px 0; margin-left: 4px; }}
  .menu div {{ white-space: pre; padding: 0 1ch; }}
  .menu .t {{ text-align: center; }}
  .menu .sel {{ background: #FFFF80; color: #0B0D0F; }}
  .menu hr {{ border: 0; border-top: 1px solid {FG}; margin: 2px 0; }}
</style></head><body>
{chr(10).join(body)}
</body></html>""")
