# Контекст сборки — корень task02/ (docker build -f configs/Dockerfile .), поэтому пути ниже от корня.
# "slim" - облегчённый вариант
FROM python:3.12.3-slim

# рабочая директория внутри контейнера
WORKDIR /app

# копируем ТОЛЬКО requirements.txt: слой с зависимостями пересобирается, только если они изменились
COPY configs/requirements.txt .

# --no-cache-dir - не сохранять кэш pip внутри образа
RUN pip install --no-cache-dir -r requirements.txt

# теперь сам код приложения - если поменяется только он, пересоберётся только этот слой
COPY src/ ./src/

# приложение работает не от root
RUN useradd --no-create-home --shell /usr/sbin/nologin app
USER app

# документирует, что приложение слушает порт 8000
EXPOSE 8000

# ARG - переменная, доступная только во время СБОРКИ образа
ARG APP_VERSION=dev

# ENV - переменная окружения УЖЕ ВНУТРИ запущенного контейнера, её читает os.environ.get("APP_VERSION")
ENV APP_VERSION=${APP_VERSION}

# проверка здоровья средствами самого образа (в slim нет curl, поэтому python)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=3)"

# gunicorn - production WSGI-сервер для Flask (см. requirements.txt).
# --bind 0.0.0.0:8000 - слушать все интерфейсы контейнера на порту 8000
# src.app:app - "в пакете src, в файле app.py, взять объект с именем app"
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "src.app:app"]
