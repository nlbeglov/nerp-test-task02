"""
Проверяем ровно те сценарии, что перечислены в требованиях задания:
  - 2 + 3 = 5
  - -2 + 1 = -1
  - отсутствующий параметр -> HTTP 400
  - нечисловой параметр -> HTTP 400
"""

import sys
import os

# добавляем папку src/ в пути поиска модулей, чтобы можно было
# написать "from app import app" - иначе Python не найдёт файл app.py,
# так как tests/ и src/ - разные папки
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from app import app

# pytest fixture - специальная функция, которая готовит "инструмент"
# для теста и передаёт его как аргумент. Здесь client - это тестовый
# клиент Flask, который умеет делать вызовы к приложению без реального
# HTTP-сервера и сети
import pytest

@pytest.fixture
def client():
    # test_client() возвращает объект с методами .get(), .post() и т.д.,
    # которые "изнутри" вызывают обработчики Flask напрямую
    app.config["TESTING"] = True
    return app.test_client()


def test_health_returns_200(client):
    response = client.get("/health")
    assert response.status_code == 200


def test_version_returns_json_with_version_field(client):
    response = client.get("/version")
    assert response.status_code == 200
    # .get_json() разбирает тело ответа как JSON и возвращает dict
    body = response.get_json()
    assert "version" in body


def test_add_two_plus_three_equals_five(client):
    response = client.get("/add?a=2&b=3")
    assert response.status_code == 200
    assert response.get_json() == {"result": 5}


def test_add_negative_two_plus_one_equals_negative_one(client):
    response = client.get("/add?a=-2&b=1")
    assert response.status_code == 200
    assert response.get_json() == {"result": -1}


def test_add_missing_parameter_returns_400(client):
    # параметр 'a' не передан вообще
    response = client.get("/add?b=3")
    assert response.status_code == 400


def test_add_non_numeric_parameter_returns_400(client):
    # 'abc' нельзя превратить в целое число
    response = client.get("/add?a=abc&b=3")
    assert response.status_code == 400


def test_add_float_parameter_returns_400(client):
    # "3.5" тоже не целое число - это граничный случай,
    # который легко пропустить при небрежной валидации
    response = client.get("/add?a=3.5&b=1")
    assert response.status_code == 400
