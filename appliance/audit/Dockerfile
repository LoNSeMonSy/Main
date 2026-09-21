FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY config.py influx.py poller.py app.py ./
COPY sources ./sources

# Nothing is mounted in, so the uid does not need to match a host user.
RUN useradd --create-home audit
USER audit

EXPOSE 5003

# Single worker on purpose, same reasoning as the alerts and trigger services: the
# per-source cursors and their locks are in-process state that must not be split
# across workers. The timeout is generous because a first poll may backfill 30 days.
CMD ["gunicorn", "--bind", "0.0.0.0:5003", "--workers", "1", "--threads", "4", \
     "--timeout", "600", "--access-logfile", "-", "app:app"]
