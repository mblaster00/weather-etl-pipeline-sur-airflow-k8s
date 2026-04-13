import json
from datetime import datetime
from google.cloud import storage


def transform():
    client = storage.Client()
    bucket = client.bucket("weather-etl-data")

    # Read raw data from Cloud Storage
    raw = json.loads(bucket.blob("raw/latest.json").download_as_text())

    transformed = {
        "city": raw["name"],
        "temperature": raw["main"]["temp"],
        "humidity": raw["main"]["humidity"],
        "description": raw["weather"][0]["description"],
        "recorded_at": datetime.utcfromtimestamp(raw["dt"]).isoformat(),
    }

    # Write transformed data to Cloud Storage
    bucket.blob("transformed/latest.json").upload_from_string(
        json.dumps(transformed)
    )

    print(f"Transformed data for {transformed['city']} successfully.")


if __name__ == "__main__":
    transform()