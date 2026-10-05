#!/usr/bin/env bash

# Скрипт запускается ВНУТРИ GitHub Actions runner.
# Его задача - подключиться к VPS по SSH и сказать серверу
# "разверни вот этот конкретный образ (по digest)".
#
# Ожидаемые переменные окружения (передаются из workflow ci-cd.yml / rollback.yml):
#   IMAGE_REF        - полная ссылка на образ вида ghcr.io/owner/repo@sha256:<64 hex>
#   APP_VERSION      - видимая версия (обычно = commit SHA)
#   SSH_HOST         - адрес VPS
#   SSH_USER         - пользователь для подключения
#   SSH_PRIVATE_KEY  - содержимое приватного ключа (многострочная переменная)
#   APP_DOMAIN       - домен сервиса (по умолчанию a2.fdghyt.com)
#   SSH_KNOWN_HOSTS  - (необязательно) строка known_hosts для VPS; если не задана,
#                      отпечаток сервера берётся через ssh-keyscan

set -euo pipefail

: "${IMAGE_REF:?IMAGE_REF не задан}"
: "${APP_VERSION:?APP_VERSION не задан}"
: "${SSH_HOST:?SSH_HOST не задан}"
: "${SSH_USER:?SSH_USER не задан}"
: "${SSH_PRIVATE_KEY:?SSH_PRIVATE_KEY не задан}"

# Значения попадают в .env на сервере и в команды на VPS, поэтому проверяем их формат заранее:
# образ - только по digest, версия - только безопасные символы
[[ "$IMAGE_REF" =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] \
    || { echo "IMAGE_REF должен иметь вид ghcr.io/owner/repo@sha256:<64 hex>, получено: $IMAGE_REF" >&2; exit 1; }
[[ "$APP_VERSION" =~ ^[A-Za-z0-9._-]+$ ]] \
    || { echo "APP_VERSION содержит недопустимые символы" >&2; exit 1; }
APP_DOMAIN="${APP_DOMAIN:-a2.fdghyt.com}"
[[ "$APP_DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] \
    || { echo "APP_DOMAIN содержит недопустимые символы" >&2; exit 1; }

# фиксированные настройки, специфичные именно для этого проекта
PROJECT_NAME="task02"
PROJECT_DIR="/opt/devops/task02"

SSH_KEY_FILE="$(mktemp)"
# приватный ключ не должен пережить скрипт ни при успехе, ни при ошибке
trap 'rm -f "$SSH_KEY_FILE"' EXIT

echo "[1/5] Готовим временный SSH-ключ"
printf '%s\n' "$SSH_PRIVATE_KEY" > "$SSH_KEY_FILE"
# приватный ключ ДОЛЖЕН иметь права 600, иначе ssh откажется его использовать
chmod 600 "$SSH_KEY_FILE"

echo "[2/5] Добавляем VPS в known_hosts"
mkdir -p ~/.ssh
if [ -n "${SSH_KNOWN_HOSTS:-}" ]; then
    # отпечаток сервера заранее сохранён в секретах: защита от подмены сервера
    printf '%s\n' "$SSH_KNOWN_HOSTS" >> ~/.ssh/known_hosts
else
    # ssh-keyscan доверяет серверу при первом подключении; надёжнее хранить known_hosts в секрете
    ssh-keyscan -H "$SSH_HOST" >> ~/.ssh/known_hosts 2>/dev/null
fi

run_remote() {
    ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=yes "${SSH_USER}@${SSH_HOST}" "$@"
}

echo "[3/5] Создаём папку проекта на VPS (если её ещё нет): на сервере та же раскладка configs/, что и в репозитории"
run_remote "mkdir -p '$PROJECT_DIR/configs'"

echo "[4/5] Копируем свежий docker-compose.yml (HTTPS обслуживает общий Caddy сервера)"
scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=yes \
    configs/docker-compose.yml \
    "${SSH_USER}@${SSH_HOST}:${PROJECT_DIR}/configs/docker-compose.yml"

echo "[5/5] Обновляем .env на сервере и перезапускаем сервис"
# Аргументы передаются в удалённый скрипт через printf %q (экранирование для удалённой оболочки),
# а сам скрипт читается из heredoc в кавычках: ничего не подставляется и не исполняется на runner'е
REMOTE_ARGS="$(printf '%q ' "$PROJECT_NAME" "$PROJECT_DIR" "$IMAGE_REF" "$APP_VERSION" "$APP_DOMAIN")"
run_remote "bash -s -- $REMOTE_ARGS" <<'REMOTE'
set -euo pipefail
PROJECT_NAME="$1"; PROJECT_DIR="$2"; IMAGE_REF="$3"; APP_VERSION="$4"; APP_DOMAIN="$5"
cd "$PROJECT_DIR/configs"

# Сохраняем предыдущий успешный выпуск: .env.previous хранит прошлые IMAGE_REF/APP_VERSION,
# по этому digest можно сделать откат (workflow Rollback)
if [ -f .env ]; then
    cp .env .env.previous
fi

cat > .env <<ENVEOF
COMPOSE_PROJECT_NAME=$PROJECT_NAME
IMAGE_REF=$IMAGE_REF
APP_VERSION=$APP_VERSION
DOMAIN=$APP_DOMAIN
ENVEOF

docker compose -p "$PROJECT_NAME" pull app
docker compose -p "$PROJECT_NAME" up -d

echo "Текущее состояние контейнеров:"
docker compose -p "$PROJECT_NAME" ps

# Журнал выпусков: время, версия, digest и digest предыдущего выпуска
PREVIOUS_REF="$(grep -m1 '^IMAGE_REF=' .env.previous 2>/dev/null | cut -d= -f2- || true)"
echo "$(date +%Y-%m-%dT%H:%M:%S%z) version=$APP_VERSION image=$IMAGE_REF previous=${PREVIOUS_REF:-none}" >> releases.log
REMOTE

echo ""
echo "Деплой выполнен: $IMAGE_REF (версия: $APP_VERSION)"
