# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM python:3.9-slim

ENV POETRY_NO_INTERACTION=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

WORKDIR  /app

RUN pip install --no-cache-dir --disable-pip-version-check poetry

COPY poetry.toml /app/
COPY pyproject.toml /app/
COPY poetry.lock /app/
RUN poetry install --only main

COPY . /app

CMD ["poetry", "run", "python", "main.py"]