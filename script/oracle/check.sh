#!/usr/bin/env bash
# Runs the whole differential comparison against the Textpattern oracle
# (start it first with script/oracle/setup.sh) and prints one line per run:
#
#   * the comparison theme in live, testing and debug modes;
#   * a crawl of the site under every permanent link mode;
#   * the comment workflow (preview, submit, replay), with and without moderation;
#   * a crawl with Textpattern's own four-point-nine theme.
#
# Every comparison is strict: bytes plus caching headers must be identical.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ORACLE="$ROOT/script/oracle"
cd "$ROOT"
failed=0

run() {
  local label="$1"; shift
  local out
  out="$(STRICT=1 ruby "$ORACLE/diff.rb" "$@")"
  local summary
  summary="$(tail -1 <<< "$out")"
  printf "%-44s %s\n" "$label" "${summary%% (*}"
  grep -q '^DIFF' <<< "$out" && { grep '^DIFF' <<< "$out" | sed 's/^/    /'; failed=1; }
}

comments() {
  local label="$1"; shift
  local out
  out="$(ruby "$ORACLE/comments.rb" "$@")"
  printf "%-44s %s\n" "$label" "$(tail -1 <<< "$out")"
  grep -q '^DIFF' <<< "$out" && { grep '^DIFF' <<< "$out" | sed 's/^/    /'; failed=1; }
}

pref() { "$ORACLE/setup.sh" pref "$1" "$2"; }

EXTRA=(/cov/ /probe/ /gone/ /private/ '/cov/?p=1' '/probe/?p=2&context=image')

reload() { "$ORACLE/setup.sh" reload > /dev/null || { echo "reload failed" >&2; exit 2; }; }

reload
for mode in live testing debug; do
  pref production_status "$mode"
  run "comparison theme, $mode"
  run "coverage pages, $mode" "${EXTRA[@]}"
done

pref production_status live
for permlinks in section_title messy id_title year_month_day_title section_id_title title_only section_category_title breadcrumb_title; do
  pref permlink_mode "$permlinks"
  run "crawl, $permlinks" --crawl=200 / '/?q=ruby' /cov/ /probe/
done
pref permlink_mode section_title

for mode in live testing; do
  pref production_status "$mode"
  comments "comments, $mode"
done
pref comments_moderate 1
comments "comments, moderated" /articles/ruby-tips
pref comments_moderate 0

THEME="$ROOT/tmp/oracle/txp49/textpattern/setup/themes/four-point-nine" reload
for mode in live testing; do
  pref production_status "$mode"
  run "four-point-nine theme crawl, $mode" --crawl=250 / '/?q=ruby' '/?q=zzzz'
done
reload

exit $failed
