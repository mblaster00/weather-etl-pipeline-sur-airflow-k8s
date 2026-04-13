import os
import json
import requests
from google.cloud import storage


def extract():
    api_key = os.environ["OPENWEATHER_API_KEY"]
    city = "Paris"

    response = requests.get(
        "https://api.openweathermap.org/data/2.5/weather",
        params={
            "q": city,
            "appid": api_key,
            "units": "metric",
        }
    )
    response.raise_for_status()

    raw_data = response.json()

    # Write raw data to Cloud Storage
    client = storage.Client()
    bucket = client.bucket("weather-etl-data")
    blob = bucket.blob("raw/latest.json")
    blob.upload_from_string(json.dumps(raw_data))

    print(f"Extracted weather data for {city} successfully.")


if __name__ == "__main__":
    extract()