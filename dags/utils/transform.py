# utils/transform.py
import json
from google.cloud import storage
from datetime import datetime

def transform():
    client = storage.Client()
    bucket = client.bucket("weather-etl-data")

    # Read from extract output
    raw = json.loads(bucket.blob("raw/latest.json").download_as_text())

    transformed = {
        "city": raw["name"],
        "temperature": raw["main"]["temp"],
        "humidity": raw["main"]["humidity"],
        "description": raw["weather"][0]["description"],
        "recorded_at": datetime.fromtimestamp(raw["dt"]).isoformat(),
    }

    # Write transformed data
    bucket.blob("transformed/latest.json").upload_from_string(
        json.dumps(transformed)
    )