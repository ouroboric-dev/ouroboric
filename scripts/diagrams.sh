#!/usr/bin/env bash
# Render diagram sources to SVG through a LOCAL Kroki, and check they are fresh.
# MVP until the docs build renders fences itself; see docs/4-ways-of-working/diagrams.md.
#
#   diagrams.sh up                 start Kroki (core + mermaid) in a Podman pod
#   diagrams.sh down               stop and remove the pod
#   diagrams.sh render <repo>...   render <repo>/docs/assets/diagrams/* to rendered/*.svg
#   diagrams.sh check <repo>...    fail if any SVG is missing or stale, or a doc marker is broken
set -euo pipefail

KROKI_URL="${KROKI_URL:-http://localhost:8000}"
KROKI_TAG="0.32.1"
POD="ouroboric-kroki"

# Diagram sources describe architecture and security controls; never send them to a third party.
case "$KROKI_URL" in
  http://localhost:*|http://127.0.0.1:*) ;;
  *) [ "${DIAGRAMS_ALLOW_REMOTE:-}" = "1" ] || { echo "refusing non-local KROKI_URL ($KROKI_URL); set DIAGRAMS_ALLOW_REMOTE=1 to override" >&2; exit 2; } ;;
esac

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

# Brand palette (docs/7-branding): Midnight #0B0D12, International Orange #FF4F00.
MERMAID_INIT='%%{init: {"theme": "base", "flowchart": {"htmlLabels": false}, "fontFamily": "\"Open Sans\", sans-serif", "themeVariables": {"primaryColor": "#FFFFFF", "primaryTextColor": "#0B0D12", "primaryBorderColor": "#0B0D12", "lineColor": "#0B0D12", "secondaryColor": "#F2F2F0", "tertiaryColor": "#FFFFFF", "clusterBkg": "#F7F7F5", "clusterBorder": "#0B0D12"}}}%%'

sources() { find "$1/docs/assets/diagrams" -maxdepth 1 -type f \( -name '*.mmd' -o -name '*.d2' -o -name '*.puml' -o -name '*.dbml' -o -name '*.vl.json' -o -name '*.excalidraw' -o -name '*.dot' \) 2>/dev/null | sort; }
base() { local b; b="$(basename "$1")"; b="${b%.vl.json}"; echo "${b%.*}"; }

cmd_up() {
  podman pod exists "$POD" && { echo "pod $POD already exists"; return; }
  # Pull public images with an empty, isolated auth config: never send the host's registry
  # credentials (or trigger its credential helpers) for these pulls.
  local auth; auth="$(mktemp -d)"; echo '{}' > "$auth/auth.json"
  export REGISTRY_AUTH_FILE="$auth/auth.json" DOCKER_CONFIG="$auth"
  podman pull -q --authfile "$auth/auth.json" "docker.io/yuzutech/kroki-mermaid:$KROKI_TAG" "docker.io/yuzutech/kroki:$KROKI_TAG" >/dev/null
  podman pod create --name "$POD" -p 127.0.0.1:8000:8000 >/dev/null
  podman run -d --pod "$POD" --name "$POD-mermaid" "docker.io/yuzutech/kroki-mermaid:$KROKI_TAG" >/dev/null
  podman run -d --pod "$POD" --name "$POD-core" -e KROKI_MERMAID_HOST=127.0.0.1 "docker.io/yuzutech/kroki:$KROKI_TAG" >/dev/null
  echo "kroki on $KROKI_URL"
}
cmd_down() { podman pod rm -f "$POD" >/dev/null && echo "removed $POD"; }

cmd_render() {
  for repo in "$@"; do
    local dir="$repo/docs/assets/diagrams" out="$repo/docs/assets/diagrams/rendered"
    mkdir -p "$out"; : > "$out/manifest.tsv.new"
    while read -r src; do
      [ -n "$src" ] || continue
      local d name body
      d="$(dialect "$src")"; name="$(base "$src")"
      if [ "$d" = mermaid ]; then body="$(printf '%s\n%s' "$MERMAID_INIT" "$(cat "$src")")"; else body="$(cat "$src")"; fi
      if ! printf '%s' "$body" | curl -sf -X POST -H 'Content-Type: text/plain' --data-binary @- "$KROKI_URL/$d/svg" -o "$out/$name.svg"; then
        echo "FAILED $src ($d)" >&2; rm -f "$out/manifest.tsv.new"; exit 1
      fi
      printf '%s\t%s\t%s\n' "$(basename "$src")" "$d" "$(sha256sum "$src" | cut -d' ' -f1)" >> "$out/manifest.tsv.new"
      echo "rendered $src"
    done < <(sources "$repo")
    mv "$out/manifest.tsv.new" "$out/manifest.tsv"
  done
}

cmd_check() {
  local bad=0
  for repo in "$@"; do
    local out="$repo/docs/assets/diagrams/rendered"
    while read -r src; do
      [ -n "$src" ] || continue
      local name want got
      name="$(base "$src")"; want="$(sha256sum "$src" | cut -d' ' -f1)"
      got="$(awk -F'\t' -v f="$(basename "$src")" '$1==f{print $3}' "$out/manifest.tsv" 2>/dev/null || true)"
      [ -f "$out/$name.svg" ] && [ "$want" = "$got" ] || { echo "STALE $src (run: diagrams.sh render $repo)"; bad=1; }
    done < <(sources "$repo")
    # every marker must name an existing source and be followed by its rendered SVG
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
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
