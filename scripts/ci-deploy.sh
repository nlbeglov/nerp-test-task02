#!/usr/bin/env bash

# Скрипт запускается ВНУТРИ GitHub Actions runner
# Его задача - подключиться к VPS по SSH и сказать серверу
# "разверни вот этот конкретный образ (по digest)".
#
# Ожидаемые переменные окружения (передаются из workflow ci-cd.yml):
#   IMAGE_REF        - полная ссылка на образ
#   APP_VERSION      - видимая версия (обычно = commit SHA)
#   SSH_HOST         - адрес VPS
#   SSH_USER         - пользователь для подключения
#   SSH_PRIVATE_KEY  - содержимое приватного ключа (многострочная переменная)

set -euo pipefail

: "${IMAGE_REF:?IMAGE_REF не задан}"
: "${APP_VERSION:?APP_VERSION не задан}"
: "${SSH_HOST:?SSH_HOST не задан}"
: "${SSH_USER:?SSH_USER не задан}"
: "${SSH_PRIVATE_KEY:?SSH_PRIVATE_KEY не задан}"

# фиксированные настройки, специфичные именно для этого проекта -
# сознательно не выношу в переменные окружения, чтобы не плодить
# лишние секреты ради значений, которые и так не меняются
PROJECT_NAME="task02"
PROJECT_DIR="/opt/task02-deploy"

echo "[1/5] Готовим временный SSH-ключ"
# mktemp создаёт файл с уникальным именем - чтобы параллельные запуски
# (если вдруг concurrency не сработает) не затирали ключи друг друга
SSH_KEY_FILE="$(mktemp)"
# записываем содержимое приватного ключа из переменной окружения в файл -
# именно файл, а не переменную, нужен команде ssh через флаг -i
echo "$SSH_PRIVATE_KEY" > "$SSH_KEY_FILE"
# приватный ключ ДОЛЖЕН иметь права 600, иначе ssh откажется его использовать
# ("Permissions are too open")
chmod 600 "$SSH_KEY_FILE"

echo "[2/5] Добавляем VPS в known_hosts"
# ssh-keyscan получает публичный отпечаток сервера заранее,
# чтобы ssh не задавал интерактивный вопрос
# "Are you sure you want to continue connecting (yes/no)?" -
# в автоматическом CI отвечать на такой вопрос некому
mkdir -p ~/.ssh
ssh-keyscan -H "$SSH_HOST" >> ~/.ssh/known_hosts 2>/dev/null

# короткая функция-обёртка, чтобы не повторять одни и те же флаги ssh
# в каждой команде ниже
run_remote() {
    ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=yes "${SSH_USER}@${SSH_HOST}" "$@"
}

echo "[3/5] Создаём папку проекта на VPS (если её ещё нет)"
# заодно создаём подпапку configs/ - именно туда docker-compose.yml
# монтирует Caddyfile (см. "./configs/Caddyfile:/etc/caddy/Caddyfile:ro")
run_remote "mkdir -p '$PROJECT_DIR/configs'"

echo "[4/5] Копируем свежие конфиги (docker-compose.yml, Caddyfile)"
# scp с тем же ключом и опциями, что и ssh выше
scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=yes \
    docker-compose.yml \
    "${SSH_USER}@${SSH_HOST}:${PROJECT_DIR}/docker-compose.yml"
# кладём Caddyfile именно в подпапку configs/ на сервере - путь должен
# совпадать с тем, что указан в volumes: docker-compose.yml
scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=yes \
    configs/Caddyfile \
    "${SSH_USER}@${SSH_HOST}:${PROJECT_DIR}/configs/Caddyfile"

echo "[5/5] Обновляем .env на сервере и перезапускаем сервис"
# heredoc (<<EOF ... EOF), переданный в run_remote, выполняется как
# единый bash-скрипт УЖЕ НА СТОРОНЕ VPS. Внутри heredoc переменные
# IMAGE_REF/APP_VERSION/PROJECT_NAME подставляются ЗДЕСЬ, на runner'е
# (потому что EOF без кавычек), поэтому на сервере окажутся их готовые
# значения, а не сами имена переменных
run_remote bash <<EOF
set -euo pipefail
cd "$PROJECT_DIR"

# перезаписываем .env целиком - так надёжнее, чем sed по частям:
# исключается риск оставить старое значение, если формат файла
# когда-то изменится
cat > .env <<ENVEOF
PROJECT_NAME=$PROJECT_NAME
IMAGE_REF=$IMAGE_REF
APP_VERSION=$APP_VERSION
ENVEOF

# затягиваем свежий образ по digest и перезапускаем только то,
# что изменилось (docker compose сам понимает, что caddy не менялся,
# и не перезапускает его без необходимости)
docker compose -p "$PROJECT_NAME" pull app
docker compose -p "$PROJECT_NAME" up -d

echo "Текущее состояние контейнеров:"
docker compose -p "$PROJECT_NAME" ps
EOF

echo ""
echo "Деплой выполнен: $IMAGE_REF (версия: $APP_VERSION)"

# подчищаем за собой временный файл с приватным ключом -
# он не должен пережить этот job дольше необходимого
rm -f "$SSH_KEY_FILE"
