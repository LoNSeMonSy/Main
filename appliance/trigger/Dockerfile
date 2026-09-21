FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# openssh-client is needed to trigger the import script on PBS after a backup.
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-client \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY config.py pve.py influx.py pbs_import.py app.py ./

# uid matches the host user that owns the mounted PBS key. ssh also requires a real
# passwd entry for its uid, so overriding the uid at runtime is not enough.
ARG APP_UID=1001
RUN useradd --create-home --uid ${APP_UID} trigger
USER trigger
ENV HOME=/home/trigger

EXPOSE 5001

# Single worker on purpose: progress-polling threads keep state in-process,
# so the job registry must not be split across workers.
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "1", "--threads", "8", \
     "--timeout", "120", "--access-logfile", "-", "app:app"]
