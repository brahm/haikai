#!/usr/bin/env bash
# Differential-testing oracle: runs the real Textpattern 4.9 (PHP 8.3 + MariaDB
# in Docker) on http://localhost:8081 and this Rails port on
# http://127.0.0.1:3001, both loaded with the same content and theme
# (script/oracle/content.rb + script/oracle/theme), so that
# script/oracle/diff.rb can compare their output byte for byte.
#
#   script/oracle/setup.sh          # build/start everything
#   script/oracle/setup.sh reload   # reload content + restart the Rails side
#   script/oracle/setup.sh stop     # stop containers and the Rails server
#   script/oracle/setup.sh pref NAME VALUE  # change a preference on both sides
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Textpattern revision the oracle runs: the 4.9.x branch when it was last
# checked (the README cites it). Bump it on purpose, then re-run check.sh.
TXP_REV="${TXP_REV:-35e52d9f01da226cf0eb89f798218cb85d6eadae}"
WORK="$ROOT/tmp/oracle"
SRC="$WORK/txp49"
WEB="$WORK/web"
SQL="$WORK/compare.sql"
DB="$ROOT/storage/compare.sqlite3"
PID="$ROOT/tmp/pids/compare.pid"
mkdir -p "$WORK" "$ROOT/tmp/pids"

stop_rails() {
  if [ -f "$PID" ]; then
    local pid
    pid="$(cat "$PID")"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
    rm -f "$PID"
  fi
}

start_rails() {
  stop_rails
  (cd "$ROOT" && DATABASE_URL="sqlite3:$DB" exec bin/rails server -p 3001 -b 127.0.0.1 -P "$PID") \
    > "$ROOT/log/compare.out" 2>&1 < /dev/null &
  for _ in $(seq 1 60); do curl -s -o /dev/null http://127.0.0.1:3001/ && return 0; sleep 1; done
  echo "Rails compare server did not start (see log/compare.out)" >&2; return 1
}

load_content() {
  # The running server keeps the database open; stale -wal/-shm files would be
  # replayed into the new database.
  stop_rails
  rm -f "$DB" "$DB-wal" "$DB-shm"
  (cd "$ROOT" && DATABASE_URL="sqlite3:$DB" bin/rails db:schema:load > /dev/null)
  (cd "$ROOT" && DATABASE_URL="sqlite3:$DB" bin/rails runner script/oracle/content.rb "$SQL")
  docker exec -i txpdb mariadb -utxp -ptxp txp < "$SQL"
}

case "${1:-start}" in
  stop)
    stop_rails
    docker stop txpphp txpdb > /dev/null 2>&1 || true
    exit 0 ;;
  reload)
    load_content
    start_rails
    exit 0 ;;
  pref)
    # script/oracle/setup.sh pref production_status testing
    docker exec txpdb mariadb -utxp -ptxp txp -e "UPDATE txp_prefs SET val = '$3' WHERE name = '$2' AND user_name = ''"
    sqlite3 "$DB" "UPDATE txp_prefs SET val = '$3' WHERE name = '$2' AND user_name = ''"
    exit 0 ;;
esac

if [ ! -d "$SRC" ]; then
  git init -q "$SRC"
  git -C "$SRC" fetch -q --depth 1 https://github.com/textpattern/textpattern.git "$TXP_REV"
  git -C "$SRC" checkout -q FETCH_HEAD
fi
if [ "$(git -C "$SRC" rev-parse HEAD)" != "$TXP_REV" ]; then
  echo "warning: $SRC is at $(git -C "$SRC" rev-parse --short HEAD), not $TXP_REV (remove tmp/oracle to fetch it)" >&2
fi
docker image inspect txp-oracle-php > /dev/null 2>&1 || docker build -q -t txp-oracle-php "$ROOT/script/oracle"
docker network create txpnet > /dev/null 2>&1 || true

fresh=0
if [ ! -d "$WEB" ]; then
  cp -r "$SRC" "$WEB" && rm -rf "$WEB/.git" && chmod -R a+rwX "$WEB"
  fresh=1
fi

docker rm -f txpphp txpdb > /dev/null 2>&1 || true
docker run -d --name txpdb --network txpnet -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=txp \
  -e MARIADB_USER=txp -e MARIADB_PASSWORD=txp mariadb:11 > /dev/null
docker run -d --name txpphp --network txpnet -p 8081:80 -v "$WEB":/var/www/html:Z txp-oracle-php > /dev/null
for _ in $(seq 1 60); do docker exec txpdb mariadb -utxp -ptxp txp -e "SELECT 1" > /dev/null 2>&1 && break; sleep 1; done

# The database container is always recreated, so Textpattern is always
# installed from scratch (setup.php refuses to run over an existing config.php).
[ "$fresh" = 1 ] || rm -f "$WEB/textpattern/config.php"
cat > "$WEB/setup.json" <<'EOF'
{
  "site": {"public_url": "http://localhost:8081", "admin_url": "http://localhost:8081/textpattern", "language_code": "en", "admin_theme": "hive", "public_theme": "four-point-nine", "content_directory": ""},
  "database": {"user": "txp", "password": "txp", "host": "txpdb", "db_name": "txp", "table_prefix": "", "charset": "utf8mb4"},
  "user": {"login_name": "admin", "password": "admin123", "email": "admin@example.com", "full_name": "Site Administrator"}
}
EOF
docker exec txpphp php /var/www/html/textpattern/setup/setup.php --config=/var/www/html/setup.json | tail -3

load_content
start_rails
echo "Oracle: http://localhost:8081  Rails: http://127.0.0.1:3001  ->  ruby script/oracle/diff.rb"
