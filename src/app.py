"""
Минимальный HTTP-сервис

Три ручки:
  GET /health  -> 200, просто подтверждает что процесс жив
  GET /version -> JSON с версией сборки (берётся из переменной окружения)
  GET /add     -> JSON {"result": a+b}, либо 400 при некорректных параметрах
"""

import os
from flask import Flask, jsonify, request

# создаём приложение Flask 
app = Flask(__name__)

# версия сервиса не зашита в коде намертво, а читается из переменной
# окружения APP_VERSION. Так мы сможем менять "видимую" версию сервиса
# только через docker-compose/.env, не трогая и не пересобирая код.
# os.environ.get(key, default) - вернёт default, если переменная не задана
# (например при локальном запуске без докера)
APP_VERSION = os.environ.get("APP_VERSION", "dev")


@app.route("/health")
def health():
    # для health-чека достаточно самого факта ответа с кодом 200 -
    # Flask по умолчанию отдаёт 200, если явно не указано иное
    return jsonify(status="ok")


@app.route("/version")
def version():
    # оборачиваем в JSON с полем version, как требует задание
    return jsonify(version=APP_VERSION)


def parse_int_param(name):
    """
    Достаёт параметр query-строки по имени и пытается превратить в int.

    Возвращает (значение, ошибка).
    Если ошибка не None - значит параметр отсутствует или не целое число,
    и вызывающий код должен вернуть 400.
    """
    # request.args - это словарь параметров из query-строки (?a=2&b=3)
    # .get(name) вернёт None, если параметра нет вообще
    raw_value = request.args.get(name)

    if raw_value is None:
        return None, f"parametr '{name}' is missing"

    try:
        # int("2") -> 2, но int("2.5") или int("abc") выбросят ValueError -
        # это ровно то поведение, которое нам нужно: "3.5" не целое число
        parsed_value = int(raw_value)
    except ValueError:
        return None, f"parametr '{name}' must be an integer, got: '{raw_value}'"

    return parsed_value, None


@app.route("/add")
def add():
    # парсим оба параметра по очереди
    a, error_a = parse_int_param("a")
    b, error_b = parse_int_param("b")

    # если хотя бы один параметр невалиден - собираем все ошибки в один
    # ответ и возвращаем HTTP 400 (Bad Request)
    errors = [e for e in (error_a, error_b) if e is not None]
    if errors:
        # jsonify(...) вторым позиционным элементом кортежа задаёт HTTP-код ответа
        return jsonify(error="; ".join(errors)), 400

    # если оба параметра успешно распознаны - считаем сумму и отдаём результат
    return jsonify(result=a + b)


# точка входа для локального запуска (python src/app.py) -
# внутри Docker-контейнера мы всё равно будем использовать gunicorn,
# поэтому этот блок нужен только для локальной отладки без докера
if __name__ == "__main__":
    # host="0.0.0.0" - слушать все сетевые интерфейсы, а не только localhost,
    # это понадобится и внутри контейнера, чтобы Caddy мог достучаться
    app.run(host="0.0.0.0", port=8000, debug=True)
