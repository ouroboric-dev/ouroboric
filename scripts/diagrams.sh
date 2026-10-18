#!/usr/bin/env bash
# Render diagram sources to SVG through a LOCAL Kroki, in the brand's light and dark themes, and check
# they are fresh. MVP until the docs build renders fences itself; see docs/4-ways-of-working/diagrams.md.
#
#   diagrams.sh up                 start Kroki (core + mermaid) in a Podman pod, with the brand font
#   diagrams.sh down               stop and remove the pod
#   diagrams.sh render <repo>...   render <repo>/docs/assets/diagrams/* to rendered/<name>.svg (light)
#                                  and rendered/<name>.dark.svg (dark)
#   diagrams.sh check <repo>...    fail if any SVG is missing or stale, or a doc marker is broken
#
# Needs podman, curl, unzip, python3 and uv (uv runs the pinned fonttools that embeds Inter in Mermaid SVGs).
set -euo pipefail

KROKI_TAG="0.32.1"
POD="ouroboric-kroki"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
# Colours come from the design tokens; the theme below maps them onto each dialect.
TOKENS="$HERE/../docs/7-branding/identity/tokens.json"

# Brand font (docs/7-branding/identity): Inter, from its official release, pinned by checksum.
INTER_URL="https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip"
INTER_SHA256="9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e"
FONT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ouroboric/fonts/inter-4.1"
FONTTOOLS="fonttools[woff]==4.60.1"
D2_FONTS=(-e D2_FONT_REGULAR=/tmp/fonts/Inter-Regular.ttf -e D2_FONT_ITALIC=/tmp/fonts/Inter-Italic.ttf
          -e D2_FONT_SEMIBOLD=/tmp/fonts/Inter-SemiBold.ttf -e D2_FONT_BOLD=/tmp/fonts/Inter-Bold.ttf)

# Kroki is reached only from inside its pod, on the pod's loopback; the pod publishes no host port.
# Diagram sources describe architecture and security controls, so they never leave the machine; and no
# host port means no port-forwarding rules, which a crashed container can leave behind to shadow the port.
# kroki <dialect>: POST stdin to Kroki, print the SVG.
kroki() { podman exec -i "$POD-core" curl -sf -X POST -H 'Content-Type: text/plain' --data-binary @- "http://127.0.0.1:8000/$1/svg"; }

dialect() {
  case "$1" in
    *.mmd) echo mermaid ;;
    *.d2) echo d2 ;;
    *.puml) grep -q 'C4_' "$1" && echo c4plantuml || echo plantuml ;;
    *.dbml) echo dbml ;;
    *.vl.json) echo vegalite ;;
    *.excalidraw) echo excalidraw ;;
    *.dot) echo graphviz ;;
    *) echo "" ;;
  esac
}

# theme <light|dark> <part>: the brand theme for one dialect, built from tokens.json.
#   mermaid-init     the %%{init}%% line: palette and font
#   mermaid-classes  the shared classes sources may use: gate, cond, inverse
#   d2-vars          the vars block: palette as D2 theme overrides, plus ${bg} ${surface} ${border}
#                    ${text} ${muted} ${accent} ${on-accent} for inline styles
theme() {
  python3 -I - "$TOKENS" "$1" "$2" <<'PY'
import json, sys
tokens, mode, part = sys.argv[1:]
t = json.load(open(tokens))[mode]
bg, surface, border, text, muted, accent, on = (t[k] for k in ("bg", "surface", "border", "text", "muted", "accent", "on-accent"))
if part == "mermaid-init":
    v = {"background": bg, "mainBkg": bg, "primaryColor": bg, "primaryTextColor": text, "primaryBorderColor": muted,
         "nodeBorder": muted, "nodeTextColor": text, "lineColor": muted, "secondaryColor": surface, "tertiaryColor": bg,
         "clusterBkg": surface, "clusterBorder": muted, "edgeLabelBackground": bg, "textColor": text, "titleColor": text}
    init = {"theme": "base", "flowchart": {"htmlLabels": False}, "fontFamily": 'Inter, "Inter Variable", sans-serif', "themeVariables": v}
    print("%%{init: " + json.dumps(init) + "}%%")
elif part == "mermaid-classes":
    print(f"classDef gate fill:{accent},color:{on},stroke:{on}")
    print(f"classDef cond fill:{bg},color:{text},stroke:{accent},stroke-width:2px,stroke-dasharray:5 3")
    print(f"classDef inverse fill:{text},color:{bg},stroke:{text}")
elif part == "d2-vars":
    o = {"N1": text, "N2": muted, "N3": muted, "N4": border, "N5": border, "N6": surface, "N7": bg,
         "B1": muted, "B2": muted, "B3": border, "B4": surface, "B5": bg, "B6": bg,
         "AA2": muted, "AA4": surface, "AA5": bg, "AB4": surface, "AB5": bg}
    ov = "; ".join(f'{k}: "{c}"' for k, c in o.items())
    vs = "; ".join(f'{k}: "{c}"' for k, c in (("bg", bg), ("surface", surface), ("border", border), ("text", text),
                                              ("muted", muted), ("accent", accent), ("on-accent", on)))
    print(f"vars: {{ d2-config: {{ theme-id: 1; theme-overrides: {{ {ov} }} }}; {vs} }}")
PY
}

sources() { find "$1/docs/assets/diagrams" -maxdepth 1 -type f \( -name '*.mmd' -o -name '*.d2' -o -name '*.puml' -o -name '*.dbml' -o -name '*.vl.json' -o -name '*.excalidraw' -o -name '*.dot' \) 2>/dev/null | sort; }
base() { local b; b="$(basename "$1")"; b="${b%.vl.json}"; echo "${b%.*}"; }
# A source is fresh when its hash and the render setup's hash (this script, the tokens) both match.
setup_hash() { cat "$SELF" "$TOKENS" | sha256sum | cut -d' ' -f1; }
themed() { case "$1" in mermaid|d2) return 0 ;; *) return 1 ;; esac; }

fetch_fonts() {
  [ -f "$FONT_DIR/InterVariable.ttf" ] && return
  local tmp; tmp="$(mktemp -d)"
  curl -sfL -o "$tmp/inter.zip" "$INTER_URL"
  echo "$INTER_SHA256  $tmp/inter.zip" | sha256sum -c --quiet - || { echo "Inter download failed its checksum; not using it" >&2; exit 1; }
  mkdir -p "$FONT_DIR"
  unzip -q -o -j "$tmp/inter.zip" InterVariable.ttf LICENSE.txt extras/ttf/Inter-Regular.ttf extras/ttf/Inter-Italic.ttf \
    extras/ttf/Inter-SemiBold.ttf extras/ttf/Inter-Bold.ttf -d "$FONT_DIR"
  rm -r -- "${tmp:?}"
}
wait_ready() {
  for _ in $(seq 60); do
    printf 'flowchart LR\n  a --> b\n' | kroki mermaid >/dev/null 2>&1 && return
    sleep 1
  done
  echo "Kroki did not become ready" >&2; exit 1
}
# Copy Inter into the pod: D2 reads the static files; Mermaid's browser measures labels with the system
# fonts, which it reads at start, so the Mermaid container restarts after the copy.
install_fonts() {
  podman pod exists "$POD" || { echo "pod $POD is not running; run: diagrams.sh up" >&2; exit 1; }
  if podman exec "$POD-core" test -f /tmp/fonts/Inter-Bold.ttf 2>/dev/null \
     && podman exec "$POD-mermaid" test -f /home/kroki/.fonts/InterVariable.ttf 2>/dev/null; then return; fi
  fetch_fonts
  podman exec "$POD-core" mkdir -p /tmp/fonts
  local f; for f in Inter-Regular Inter-Italic Inter-SemiBold Inter-Bold; do podman cp "$FONT_DIR/$f.ttf" "$POD-core:/tmp/fonts/"; done
  podman exec "$POD-mermaid" mkdir -p /home/kroki/.fonts
  podman cp "$FONT_DIR/InterVariable.ttf" "$POD-mermaid:/home/kroki/.fonts/"
  podman exec "$POD-mermaid" fc-cache --force >/dev/null 2>&1
  podman restart "$POD-mermaid" >/dev/null
  wait_ready
}

cmd_up() {
  if ! podman pod exists "$POD"; then
    # Pull public images with an empty, isolated auth config: never send the host's registry
    # credentials (or trigger its credential helpers) for these pulls.
    local auth; auth="$(mktemp -d)"; echo '{}' > "$auth/auth.json"
    export REGISTRY_AUTH_FILE="$auth/auth.json" DOCKER_CONFIG="$auth"
    podman pull -q --authfile "$auth/auth.json" "docker.io/yuzutech/kroki-mermaid:$KROKI_TAG" "docker.io/yuzutech/kroki:$KROKI_TAG" >/dev/null
    podman pod create --name "$POD" >/dev/null
    podman run -d --pod "$POD" --name "$POD-mermaid" "docker.io/yuzutech/kroki-mermaid:$KROKI_TAG" >/dev/null
    podman run -d --pod "$POD" --name "$POD-core" -e KROKI_MERMAID_HOST=127.0.0.1 "docker.io/yuzutech/kroki:$KROKI_TAG" >/dev/null
    wait_ready
  fi
  install_fonts
  echo "kroki in pod $POD, with Inter"
}
cmd_down() { podman pod rm -f "$POD" >/dev/null && echo "removed $POD"; }

# Embed the glyphs a Mermaid SVG uses from Inter, so it renders in Inter wherever it is shown (an SVG
# shown as an image can't load web fonts), and paint the theme background.
finish_mermaid() {
  local svg="$1" bg="$2" tmp; tmp="$(mktemp -d)"
  python3 -I - "$svg" "$tmp/text.txt" <<'PY'
import html, re, string, sys
svg = re.sub(r"<style.*?</style>", "", open(sys.argv[1], encoding="utf-8").read(), flags=re.S)
chars = set(string.printable.strip()) | set("".join(html.unescape(m) for m in re.findall(r">([^<>]+)<", svg)))
open(sys.argv[2], "w", encoding="utf-8").write("".join(sorted(c for c in chars if not c.isspace())))
PY
  uvx -q --from "$FONTTOOLS" pyftsubset "$FONT_DIR/InterVariable.ttf" --text-file="$tmp/text.txt" \
    --flavor=woff2 --layout-features='kern,liga,calt' --output-file="$tmp/inter.woff2" 2>/dev/null
  [ -s "$tmp/inter.woff2" ] || { echo "embedding Inter failed for $svg" >&2; rm -r -- "${tmp:?}"; return 1; }
  python3 -I - "$svg" "$tmp/inter.woff2" "$bg" <<'PY'
import base64, re, sys
path, font, bg = sys.argv[1:]
svg = open(path, encoding="utf-8").read()
face = ('<style>@font-face{font-family:"Inter";font-style:normal;font-weight:100 900;'
        'src:url(data:font/woff2;base64,' + base64.b64encode(open(font, "rb").read()).decode() + ') format("woff2");}</style>')
root = re.search(r"<svg\b[^>]*>", svg)
tag = root.group(0)
if 'style="' in tag:
    tag = re.sub(r'style="([^"]*)"', lambda m: 'style="' + re.sub(r"background-color:[^;]*;?", "", m.group(1)).rstrip("; ") + f'; background-color: {bg};"', tag, count=1)
else:
    tag = tag[:-1] + f' style="background-color: {bg};">'
open(path, "w", encoding="utf-8").write(svg[:root.start()] + tag + face + svg[root.end():])
PY
  rm -r -- "${tmp:?}"
}

# render_one <src> <dialect> <mode> <out.svg>
render_one() {
  local src="$1" d="$2" mode="$3" svg="$4" err
  case "$d" in
    mermaid)
      { theme "$mode" mermaid-init; cat "$src"; echo; theme "$mode" mermaid-classes; } \
        | kroki mermaid > "$svg" || return 1
      finish_mermaid "$svg" "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["bg"])' "$TOKENS" "$mode")" || return 1 ;;
    d2)
      # D2 runs in the local pod rather than through Kroki's HTTP API: only the CLI accepts custom fonts.
      err="$(mktemp)"
      if ! { theme "$mode" d2-vars; cat "$src"; } | podman exec -i "${D2_FONTS[@]}" "$POD-core" d2 - - 2>"$err" > "$svg"; then
        grep -v '^info:' "$err" >&2; rm -f -- "${err:?}"; return 1
      fi
      rm -f -- "${err:?}" ;;
    *)
      kroki "$d" < "$src" > "$svg" ;;
  esac
}

cmd_render() {
  install_fonts
  local setup; setup="$(setup_hash)"
  for repo in "$@"; do
    local out="$repo/docs/assets/diagrams/rendered"
    mkdir -p "$out"; : > "$out/manifest.tsv.new"
    while read -r src; do
      [ -n "$src" ] || continue
      local d name
      d="$(dialect "$src")"; name="$(base "$src")"
      if ! render_one "$src" "$d" light "$out/$name.svg" || { themed "$d" && ! render_one "$src" "$d" dark "$out/$name.dark.svg"; }; then
        echo "FAILED $src ($d)" >&2; rm -f -- "${out:?}/manifest.tsv.new"; exit 1
      fi
      printf '%s\t%s\t%s\t%s\n' "$(basename "$src")" "$d" "$(sha256sum "$src" | cut -d' ' -f1)" "$setup" >> "$out/manifest.tsv.new"
      echo "rendered $src"
    done < <(sources "$repo")
    mv "$out/manifest.tsv.new" "$out/manifest.tsv"
  done
}

cmd_check() {
  local bad=0 setup; setup="$(setup_hash)"
  for repo in "$@"; do
    local out="$repo/docs/assets/diagrams/rendered"
    while read -r src; do
      [ -n "$src" ] || continue
      local name want got d
      name="$(base "$src")"; d="$(dialect "$src")"; want="$(sha256sum "$src" | cut -d' ' -f1)	$setup"
      got="$(awk -F'\t' -v f="$(basename "$src")" '$1==f{print $3"\t"$4}' "$out/manifest.tsv" 2>/dev/null || true)"
      if [ ! -f "$out/$name.svg" ] || { themed "$d" && [ ! -f "$out/$name.dark.svg" ]; } || [ "$want" != "$got" ]; then
        echo "STALE $src (run: diagrams.sh render $repo)"; bad=1
      fi
    done < <(sources "$repo")
    # every marker must name an existing source and be followed by its rendered SVG
    # shellcheck disable=SC2016  # the awk program is single-quoted on purpose; the shell must not expand it
    while IFS=: read -r file _ marker; do
      local srcrel; srcrel="$(sed -E 's/.*<!-- diagram: ([^ ]+) -->.*/\1/' <<<"$marker")"
      [ -f "$repo/docs/$srcrel" ] || { echo "BROKEN MARKER $file -> $srcrel"; bad=1; }
    done < <(find "$repo/docs" -name '*.md' -print0 | xargs -0 awk '/^```/{f=!f; next} !f && /<!-- diagram: /{print FILENAME":"FNR":"$0}')
  done
  [ "$bad" = 0 ] && echo "diagrams fresh" || exit 1
}

case "${1:-}" in
  up) cmd_up ;; down) cmd_down ;;
  render) shift; cmd_render "$@" ;; check) shift; cmd_check "$@" ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
