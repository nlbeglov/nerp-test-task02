# 02. Сборка, доставка и откат

GitHub Actions · GHCR · Docker Compose · Caddy. Небольшой HTTP-сервис на Python, доставка на VPS после успешных тестов и откат на ранее опубликованный образ без пересборки.

## Схема сервисов

Один VPS: Senko Digital (Хельсинки, Финляндия), 2 vCPU / 4 GB RAM / disk: 60 GB. Домен: `a2.fdghyt.com`. Compose-проект `task02`; HTTPS обслуживает общий Caddy (`common/caddy`).

```
git push ─► GitHub Actions: тесты ─► сборка ─► публикация в GHCR ─► доставка на VPS по digest ─► проверка /health, /version
Интернет ─► общий Caddy :80/:443 ──(сеть edge)──► app :8000
```

| Сервис | Образ | Назначение |
|---|---|---|
| app | `ghcr.io/nlbeglov/nerp-test-task02@<digest>` | Flask-сервис (`src/app.py`): `/health`, `/version`, `/add?a=&b=`; версия из `APP_VERSION` (= commit SHA) |
| общий Caddy | `caddy:2.11.4` | reverse proxy, HTTPS; проксирует `a2.fdghyt.com` на `task02-app:8000` через сеть `edge` |

Образ `app` не собирается на сервере: он публикуется в GHCR и разворачивается по конкретному digest (не по тегу и не по `latest`).

Структура каталога (внутри репозитория GitHub `task02/` является его корнем):
```
task02/
	src/  tests/                     исходный код и автотесты
	.github/workflows/               ci-cd.yml (тесты → сборка → GHCR → доставка), rollback.yml (ручной откат)
	configs/   Dockerfile, docker-compose.yml, requirements.txt, .env.example
	scripts/   ci-deploy.sh (доставка из CI), check.sh (проверка)
	evidence/  подтверждения по требованиям
```
На VPS при доставке из CI та же раскладка создаётся в `/opt/devops/task02/configs/` (compose, `.env` с текущим выпуском, `.env.previous` — предыдущий выпуск, `releases.log`).

## Порты

| Порт | Назначение | Доступность |
|---|---|---|
| 22 | SSH к VPS (доставка из CI/CD) | публично |
| 80 | HTTP → редирект на HTTPS (общий Caddy) | публично |
| 443 | HTTPS (общий Caddy → app) | публично |
| 8000 | Flask/gunicorn (внутри контейнера) | только сеть `edge` (между контейнерами) |

## Команды запуска и проверки

Репозиторий склонирован на сервер в `/opt/devops` (корневой [README](../README.md)), Docker установлен, Docker установлен. Общий Caddy (`../common/caddy`) уже запущен (см. корневой [README](../README.md)), сеть `edge` создана, A-запись `a2.fdghyt.com` указывает на VPS.

Запуск на VPS из готового образа (без GitHub Actions; образ и версия по умолчанию записаны в `configs/.env.example`):
```bash
cd /opt/devops/task02/configs
cp .env.example .env && nano .env        # DOMAIN=a2.fdghyt.com; при необходимости IMAGE_REF (только по digest) и APP_VERSION
docker compose pull app && docker compose up -d
docker compose ps
```
Откат вручную: подставить в `.env` другие `IMAGE_REF` и `APP_VERSION`, затем снова `docker compose pull app && docker compose up -d`. Если пакет в GHCR приватный: `echo <токен read:packages> | docker login ghcr.io -u <логин> --password-stdin`.

Проверка (автотесты, образ по digest, `/health`, `/version`, сложение, ответы 400, редирект):
```bash
../scripts/check.sh                      # SKIP_TESTS=1 пропускает автотесты
curl -s https://a2.fdghyt.com/health
curl -s https://a2.fdghyt.com/version
curl -s "https://a2.fdghyt.com/add?a=2&b=3"
```

Тесты и сборка локально:
```bash
cd /opt/devops/task02
python3 -m venv .venv && .venv/bin/pip install -r configs/requirements.txt
.venv/bin/python -m pytest tests/ -v
docker build -f configs/Dockerfile --build-arg APP_VERSION=test-A -t task02-app:test .
```

CI/CD (после настройки репозитория GitHub, см. «Ручные действия»):
- доставка: автоматически при `git push origin main` (`.github/workflows/ci-cd.yml`);
- откат: GitHub → Actions → Rollback → Run workflow, поля `image_digest` (`sha256:…`) и `app_version`; образ не пересобирается;
- следующий обычный выпуск после отката: новый `git push` в `main` — тесты, сборка нового образа, доставка по новому digest.

Подтверждения по требованиям (команды, вывод, ссылки):

| Требование | Что показано | Файл |
|---|---|---|
| 1 | репозиторий и сервис | [Требование 1](<evidence/Требование 1.md>) |
| 2 | тесты, Dockerfile, Compose, HTTPS | [Требование 2](<evidence/Требование 2.md>) |
| 3 | CI/CD: тесты → сборка → GHCR → доставка по digest | [Требование 3](<evidence/Требование 3.md>) |
| 4 | проверка после доставки, предыдущий digest, `concurrency` | [Требование 4](<evidence/Требование 4.md>) |
| 5 | версии A и B, сломанная ревизия | [Требование 5](<evidence/Требование 5.md>) |
| 6 | ручной откат без пересборки | [Требование 6](<evidence/Требование 6.md>) |

## Зависимости от common
`check.sh` подключает `../common/lib.sh`. CI/CD-скрипт `ci-deploy.sh` от `common/` не зависит: он работает в отдельном репозитории GitHub. HTTPS обслуживает общий Caddy из `../common/caddy`; проект Compose порты 80/443 не занимает.

## Ручные действия
- Репозиторий GitHub (`nlbeglov/nerp-test-task02`): содержимое `task02/` публикуется как корень этого репозитория обычным коммитом поверх его истории: `git clone https://github.com/nlbeglov/nerp-test-task02.git sync && rsync -a --delete --exclude=.git --exclude=.venv task02/ sync/ && cd sync && git add -A && git commit -m "..." && git push`. Выпуски A, B, ошибочная ревизия и откат выполняются отдельными коммитами и запусками Rollback (порядок описан в RESULT.md).
- Секреты репозитория `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY` и (необязательно) `SSH_KNOWN_HOSTS`; отдельная пара ключей для CI (`ssh-keygen -t ed25519`, публичная часть в `authorized_keys` на VPS); создание среды `production`.
- DNS: A-запись домена на IP VPS; запустить общий Caddy (`common/caddy`) и создать сеть `edge`.
- Намеренная ошибка в сложении (`src/app.py`) и её откат выполняются локальными коммитами; запуск Rollback — кнопкой «Run workflow» с digest и версией из лога сборки.
