#!/usr/bin/env bash
# Использование: ./scripts/check.sh
# Проверяет задание 02 целиком: автотесты в виртуальном окружении, образ по digest, /health, /version
# (значение APP_VERSION из configs/.env), сложение, ошибки 400, редирект на HTTPS.
# Переменная SKIP_TESTS=1 пропускает автотесты. Код возврата: 0 — всё прошло, 1 — есть провалы.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$PROJECT_DIR/configs"
# shellcheck disable=SC1091
if [ -f "$PROJECT_DIR/../common/lib.sh" ]; then
    source "$PROJECT_DIR/../common/lib.sh"
else
    # task02 может лежать отдельным репозиторием GitHub без каталога common/: минимальный набор тех же функций
    stamp() { date +%Y-%m-%dT%H:%M:%S%z; }
    die() { echo "ОШИБКА: $*" >&2; exit 1; }
    env_get() { [ -f "$1" ] || return 0; KEY="$2" awk -F= 'BEGIN{k=ENVIRON["KEY"]} $1==k{sub(/^[^=]*=/,""); print; exit}' "$1"; }
    load_env() { local f="$1/.env" v; shift; [ -f "$f" ] || die "нет $f"; set -a; source "$f"; set +a
        for v in "$@"; do [ -n "${!v:-}" ] && [[ "${!v}" != *CHANGE_ME* ]] || die "в $f не заполнена $v"; done; }
    http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" || true; }
    CHECK_FAILED=0
    ok()   { echo "  OK    $*"; }
    warn() { echo "  WARN  $*"; }
    fail() { echo "  FAIL  $*"; CHECK_FAILED=1; }
    check_summary() { echo ""; if [ "$CHECK_FAILED" -eq 0 ]; then echo "ИТОГ: все проверки пройдены"; else echo "ИТОГ: есть провалы"; return 1; fi; }
fi
load_env "$CONFIGS_DIR" DOMAIN IMAGE_REF APP_VERSION
BASE="https://${DOMAIN}"

echo "Проверка: $(stamp)   домен: $DOMAIN"

echo ""
echo "[1/4] Автотесты (2+3=5, -2+1=-1, отсутствующий и нечисловой параметр -> 400)"
if [ "${SKIP_TESTS:-}" = "1" ]; then
    warn "пропущено (SKIP_TESTS=1)"
elif ! command -v python3 >/dev/null; then
    warn "python3 не найден: apt-get install -y python3-venv"
else
    VENV="$PROJECT_DIR/.venv"
    if [ ! -x "$VENV/bin/pytest" ]; then
        python3 -m venv "$VENV" && "$VENV/bin/pip" install -q -r "$CONFIGS_DIR/requirements.txt"
    fi
    if (cd "$PROJECT_DIR" && "$VENV/bin/python" -m pytest tests/ -q); then ok "тесты пройдены"; else fail "тесты не пройдены"; fi
fi

echo ""
echo "[2/4] Контейнеры и образ по digest"
(cd "$CONFIGS_DIR" && docker compose ps)
APP_ID="$(cd "$CONFIGS_DIR" && docker compose ps -q app)"
if [ -n "$APP_ID" ]; then
    RUNNING_IMAGE="$(docker inspect --format '{{.Config.Image}}' "$APP_ID")"
    [ "$RUNNING_IMAGE" = "$IMAGE_REF" ] && ok "app запущен из $RUNNING_IMAGE" || fail "app запущен из $RUNNING_IMAGE, ожидался $IMAGE_REF"
    case "$RUNNING_IMAGE" in *@sha256:*) ok "образ закреплён по digest" ;; *) fail "образ не закреплён по digest" ;; esac
else
    fail "контейнер app не запущен"
fi
if [ -f "$CONFIGS_DIR/.env.previous" ]; then ok "digest предыдущего выпуска сохранён: $(env_get "$CONFIGS_DIR/.env.previous" IMAGE_REF | sed 's/.*@//')"
else warn "предыдущего выпуска нет (.env.previous создаётся при втором выпуске)"; fi

echo ""
echo "[3/4] HTTPS-ответы сервиса"
[ "$(http_code "$BASE/health")" = "200" ] && ok "/health -> 200" || fail "/health не вернул 200"
VERSION="$(curl -s --max-time 10 "$BASE/version" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("version", ""))' 2>/dev/null)"
[ "$VERSION" = "$APP_VERSION" ] && ok "/version -> $VERSION" || fail "/version -> '$VERSION', ожидалось '$APP_VERSION'"
[ "$(curl -s --max-time 10 "$BASE/add?a=2&b=3" | tr -d ' \n')" = '{"result":5}' ] && ok "/add?a=2&b=3 -> {\"result\":5}" || fail "2+3 не равно 5"
[ "$(curl -s --max-time 10 "$BASE/add?a=-2&b=1" | tr -d ' \n')" = '{"result":-1}' ] && ok "/add?a=-2&b=1 -> {\"result\":-1}" || fail "-2+1 не равно -1"

echo ""
echo "[4/4] Ошибки параметров и редирект"
for URL in "/add?b=3" "/add?a=abc&b=3" "/add?a=2" "/add?a=3.5&b=1"; do
    CODE="$(http_code "$BASE$URL")"
    [ "$CODE" = "400" ] && ok "$URL -> 400" || fail "$URL -> $CODE (ожидалось 400)"
done
CODE="$(http_code "http://${DOMAIN}/health")"
case "$CODE" in 301|302|307|308) ok "http -> редирект $CODE" ;; *) fail "http -> $CODE (ожидался редирект на HTTPS)" ;; esac

check_summary
