#!/usr/bin/env bash
#
# check-linkage-pages_test.sh — --for-tag looks for "Released: vX.Y.Z" on every page of the milestones.
#
# GitHub lists at most 100 milestones a page, and a repository's closed theme milestones only accumulate,
# so the theme milestone a tag ships can sit on the second page. Hermetic: a stub `gh` serves 100 closed
# themes on page 1 and the theme milestone #200, whose description says "Released: v1.0.1", on page 2, as
# gh does: one page without --paginate, the pages merged with it, an array of pages with --slurp, and
# --jq applied to each page.

set -uo pipefail

name="for-tag: the milestone that says Released: on the second page of milestones is the one checked"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/check-linkage.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-linkage-pages.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

if ! command -v jq >/dev/null 2>&1; then printf 'not ok - %s\n     jq not found on PATH\n' "$name"; exit 1; fi

fx="$tmp/fx"; bin="$tmp/bin"; mkdir -p "$fx" "$bin"
jq -nc '[range(1; 101) | {number: ., title: "M0.\(.) — old theme", state: "closed", description: "Released: v0.\(.).0"}]' > "$fx/page1.json"
jq -nc '[{number: 200, title: "M1 — first run", state: "open", description: "Theme of the run.\nReleased: v1.0.1"}]' > "$fx/page2.json"
echo '[]' > "$fx/empty.json"
echo '[{"number":2,"state":"closed","pull_request":{}}]' > "$fx/items-200.json"   # a merged technical PR: #200 is tag-ready
echo '[{"number":9,"state":"open"}]' > "$fx/items-other.json"                   # any other milestone is not

cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
fx="${FIXTURES:?}"
all="$*"
unexpected() { echo "stub gh: unexpected call: gh $all" >&2; exit 99; }
cmd="${1:-}"; [ $# -gt 0 ] && shift
expr=""; paginate=0; slurp=0; positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --jq|-q) shift; expr="${1:-}" ;;
    --paginate) paginate=1 ;;
    --slurp) slurp=1 ;;
    --repo|-R|--json|-H|--header|-X|--method|-f|-F|--field|--raw-field) shift ;;
    --silent|-i|--include) ;;
    *) positional+=("$1") ;;
  esac
  shift
done
serve() { # page files, printed as gh prints them
  [ $# -gt 0 ] || set -- "$fx/empty.json"
  if [ "$slurp" = 1 ]; then jq -sc . "$@"
  elif [ -n "$expr" ]; then for f in "$@"; do jq -r "$expr" "$f"; done
  else jq -sc 'add' "$@"; fi
}
case "$cmd" in
  api)
    path="${positional[0]:-}"; path="${path#/}"
    case "$path" in
      "repos/$REPO/milestones"|"repos/$REPO/milestones?"*)
        page=1
        case "$path" in *'?page='[0-9]*|*'&page='[0-9]*) page="${path##*[?&]page=}"; page="${page%%[!0-9]*}" ;; esac
        files=()
        for p in 1 2; do
          if [ "$p" = "$page" ] || { [ "$paginate" = 1 ] && [ "$p" -gt "$page" ]; }; then files+=("$fx/page$p.json"); fi
        done
        serve "${files[@]}" ;;
      "repos/$REPO/milestones/"[0-9]*)
        ms=$(jq -c --argjson n "${path##*/}" '.[] | select(.number == $n)' "$fx/page1.json" "$fx/page2.json")
        [ -n "$ms" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
        if [ -n "$expr" ]; then jq -r "$expr" <<<"$ms"; else echo "$ms"; fi ;;
      "repos/$REPO/issues?"*)
        case "$path" in
          *'milestone=200&'*|*'milestone=200') serve "$fx/items-200.json" ;;
          *) serve "$fx/items-other.json" ;;
        esac ;;
      *) unexpected ;;
    esac ;;
  pr)
    [ "${positional[0]:-}" = view ] && [ "${positional[1]:-}" = 2 ] || unexpected
    pr='{"number":2,"title":"PR 2","state":"MERGED","body":"","milestone":{"title":"M1 — first run"},"closingIssuesReferences":[],"author":{"login":"dev","is_bot":false},"headRefName":"feat/x","baseRefName":"main","headRefOid":"headsha"}'
    if [ -n "$expr" ]; then jq -r "$expr" <<<"$pr"; else echo "$pr"; fi ;;
  *) unexpected ;;
esac
STUB
chmod +x "$bin/gh"

out="$(PATH="$bin:$PATH" REPO=galax-io/test BACKLOG_REPO=galax-io/backlog FEATURE_LINK=optional FIXTURES="$fx" bash "$script" --for-tag v1.0.1 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF 'Milestone: #200  M1 — first run' <<<"$out"; then
  printf 'ok - %s\n' "$name"
  exit 0
fi
printf 'not ok - %s\n     rc=%s\n%s\n' "$name" "$rc" "$out"
exit 1
