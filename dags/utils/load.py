# utils/load.py
import json
import os
import psycopg2
from google.cloud import storage

def load():
    client = storage.Client()
    bucket = client.bucket("weather-etl-data")

    # Read from transform output
    data = json.loads(
        bucket.blob("transformed/latest.json").download_as_text()
    )

    # Connect to Cloud SQL — no password, Workload Identity handles auth
    conn = psycopg2.connect(
        host=os.environ["CLOUDSQL_HOST"],
        database="weather",
        user="airflow-pods-sa",
    )

    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO weather_data (city, temperature, humidity, description, recorded_at)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (city, recorded_at) DO NOTHING
        """, (
            data["city"],
            data["temperature"],
            data["humidity"],
            data["description"],
            data["recorded_at"],
        ))
    conn.commit()