## 1. Общая информация
- Номер задания: 02
- Дата: 22.09.2026 – 06.10.2026
- Затраченные часы: 16

## 2. Ссылки
| Адрес | Назначение |
|---|---|
| https://a2.fdghyt.com | HTTPS-адрес развёрнутого сервиса (общий Caddy → app): `/health`, `/version`, `/add` |
| [github.com/nlbeglov/nerp-test-task02](https://github.com/nlbeglov/nerp-test-task02) | репозиторий |
| [Actions](https://github.com/nlbeglov/nerp-test-task02/actions) | журналы CI/CD |
| [Packages](https://github.com/nlbeglov/nerp-test-task02/pkgs/container/nerp-test-task02) | образы в GHCR |

- Репозиторий: [github.com/nlbeglov/nerp-test-task02](https://github.com/nlbeglov/nerp-test-task02)
- Финальный (задеплоенный) коммит: `83a3acd55071798f0c6dbe84d1a3697f86bd6ed5` («Fix flaky health check: retry loop instead of fixed sleep 5»)
- Ошибочная ревизия: `f34b487a58471b433cdc8b0aeb1e22c1a22de6c3` («Broken release: off-by-one bug in addition»)

## 3. Сервисы и характеристики
| Сервис | Образ | Версия/тег |
|---|---|---|
| app | ghcr.io/nlbeglov/nerp-test-task02 | по digest (таблица ниже) |
| Caddy (общий, `common/caddy`) | caddy | 2.11.4 |

- VPS: Senko Digital (Хельсинки, Финляндия), общий с заданием 01: 2 vCPU / 4GB RAM / disk: 60GB, 144.31.119.139

## 4. Статус требований
| № | Требование | Статус | Подтверждение |
|---|---|---|---|
| 1 | Репозиторий и сервис: `/health` → 200, `/version` → JSON, `/add` → JSON или 400 | выполнено | [Требование 1](<evidence/Требование 1.md>) |
| 2 | Автотесты, Dockerfile, Compose, HTTPS через Caddy, без БД | выполнено | [Требование 2](<evidence/Требование 2.md>) |
| 3 | GitHub Actions: тесты → сборка → GHCR → доставка по digest, привязка к commit | выполнено | [Требование 3](<evidence/Требование 3.md>) |
| 4 | Проверка `/health` и `/version`, digest предыдущего выпуска, `concurrency`, секреты в CI/CD | выполнено | [Требование 4](<evidence/Требование 4.md>) |
| 5 | Версии A и B, затем ошибка в сложении: тест падает, на VPS остаётся рабочая версия | выполнено | [Требование 5](<evidence/Требование 5.md>) |
| 6 | Ручной откат на готовый digest без пересборки, проверка `/version`, `/health`, сложения | выполнено | [Требование 6](<evidence/Требование 6.md>) |

## 5. Проверка за 5 минут
Действия:
1. `curl -s https://a2.fdghyt.com/health`
2. `curl -s https://a2.fdghyt.com/version`
3. `curl -s "https://a2.fdghyt.com/add?a=2&b=3"`
4. Открыть [Actions](https://github.com/nlbeglov/nerp-test-task02/actions): прогон коммита `f34b487` красный на шаге `test`.
5. Открыть [Packages](https://github.com/nlbeglov/nerp-test-task02/pkgs/container/nerp-test-task02): опубликовано три версии образа, образа для `f34b487` нет.

Автоматически на сервере: `cd /opt/devops/task02/configs && ../scripts/check.sh` (тесты, образ по digest, `/health`, `/version`, сложение, ответы 400, редирект).

Ожидаемый результат:
- `/health` → `{"status":"ok"}`, `/version` → `{"version":"83a3acd55071798f0c6dbe84d1a3697f86bd6ed5"}`, сложение → `{"result":5}`;
- прогон с ошибкой в сложении завершается `Failure` на тестах, шаги `build` и `deploy` не выполняются;
- в GHCR нет образа из сломанного коммита.

### Версия — commit — digest
| Версия (`/version`) | Коммит | Digest образа | Итог прогона CI/CD |
|---|---|---|---|
| `0f7757e…` («Release A») | [0f7757e](https://github.com/nlbeglov/nerp-test-task02/commit/0f7757e1d870a9c5695e6c9ccb77db98bd0db142) | `sha256:1215ec704ac16558e027d5d16e01554a6caa6de98797fec5104e684b143c3820` | тесты и сборка ✅, доставка ❌ ([run #1](https://github.com/nlbeglov/nerp-test-task02/actions/runs/35784102030), неверный путь на VPS) |
| `443ffee…` («Fix deploy path») | [443ffee](https://github.com/nlbeglov/nerp-test-task02/commit/443ffee3b40fff4f8a10e8954d4114dfcf88b760) | `sha256:1178957ad493913539154a4031a00dd1cd7c9029113f1258b5d9202703459c5b` | тесты, сборка, доставка ✅, проверка ❌ ([run #2](https://github.com/nlbeglov/nerp-test-task02/actions/runs/35866968117), SSL-таймаут сразу после рестарта Caddy) |
| `83a3acd…` («Fix flaky health check») | [83a3acd](https://github.com/nlbeglov/nerp-test-task02/commit/83a3acd55071798f0c6dbe84d1a3697f86bd6ed5) | `sha256:b764d0dcbe404558bb7330efe8455f4d6be613279592e374f449858d8aa82519` | полный успех ✅ ([run #3](https://github.com/nlbeglov/nerp-test-task02/actions/runs/35869160966)); работает на VPS |
| `f34b487…` («Broken release») | [f34b487](https://github.com/nlbeglov/nerp-test-task02/commit/f34b487a58471b433cdc8b0aeb1e22c1a22de6c3) | образ не собирался | `test` упал (`{"result": 5} == {"result": 6}`), `build` и `deploy` пропущены ([run #4](https://github.com/nlbeglov/nerp-test-task02/actions/runs/35870161134)) |

Откаты (workflow `Rollback`, без пересборки): [run #1](https://github.com/nlbeglov/nerp-test-task02/actions/runs/35870980191) — `Failure`; [run #2](https://github.com/nlbeglov/nerp-test-task02/actions/runs/35876611691) — `Success` (23.09, 17:46 GMT+3): время совпадает со стартом контейнера `task02-app-1` (`StartedAt: 2026-09-23T14:46:33Z`), `/version` отдаёт digest `83a3acd`.

## Проблемы и ограничения
- **Сценарий «версии A и B» (требование 5).** «Release A» (`0f7757e`) прошёл тесты и сборку, но не задеплоился из-за неверного пути на VPS; следующий коммит `443ffee` задеплоился, но проверка `/health` не прошла сразу после рестарта Caddy. Полный цикл test → build → deploy → verify завершился только на `83a3acd`, поэтому отдельной независимой версии B нет. Ключевое поведение подтверждено: ошибка в тесте не пропускает ревизию на VPS, рабочая версия остаётся.
- **Параметры двух запусков Rollback не восстановлены:** введённые в форму `image_digest` и `app_version` не видны без авторизации. Вероятно, `Rollback #1` целился в digest `0f7757e` (никогда не разворачивался на этом VPS) и упал, а `Rollback #2` откатил на `83a3acd`. Механизм отката (готовый образ по digest, тот же `ci-deploy.sh`, без сборки) подтверждён.
- Код в этом каталоге доработан после выпуска `83a3acd` (проверка версии и сложения после доставки, сохранение предыдущего digest, проверка входов отката, непривилегированный пользователь в образе, строгая проверка целых чисел). Прогоны CI/CD в таблице выше относятся к предыдущей версии workflow; новая версия проверена локально (9 тестов проходят) и на сервере (`scripts/check.sh`), а её прогон в GitHub Actions нужно подтвердить после публикации содержимого `task02/` как корня репозитория GitHub (см. README, «Ручные действия»).
- Стенд перенесён на общий Caddy: `compose`, `Dockerfile`, `requirements.txt` и `.env.example` лежат в `configs/`, домен `a2.fdghyt.com`, `docker compose` запущен из `/opt/devops/task02/configs`, образ — тот же digest `sha256:b764d0dc…` (выпуск `83a3acd`). Проверка на сервере 06.10.2026: `scripts/check.sh` — «все проверки пройдены» (тесты, образ по digest, `/health`, `/version`, сложение, 400, редирект).
- В `evidence/` нет скриншотов: подтверждения даны выводом команд и ссылками на публичные страницы GitHub Actions и GHCR.
