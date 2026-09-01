import os
import time

import mlflow
import pandas as pd
from fastapi import FastAPI, HTTPException
from mlflow import MlflowClient
from pydantic import BaseModel, Field

FEATURES = ["trip_distance", "pickup_hour", "pickup_dow", "PULocationID", "DOLocationID"]
MLFLOW_TRACKING_URI = os.getenv(
    "MLFLOW_TRACKING_URI",
    "http://mlflow.mlops-platform.svc.cluster.local:5000",
)
MODEL_NAME = os.getenv("MODEL_NAME", "TaxiDurationXGB")
MODEL_ALIAS = os.getenv("MODEL_ALIAS", "candidate")
MODEL_VERSION = os.getenv("MODEL_VERSION", "")


class TaxiTrip(BaseModel):
    trip_distance: float = Field(ge=0)
    pickup_hour: int = Field(ge=0, le=23)
    pickup_dow: int = Field(ge=0, le=6)
    PULocationID: int = Field(gt=0)
    DOLocationID: int = Field(gt=0)


app = FastAPI(title="NYC Taxi duration predictor")
model = None
loaded_model_version = ""


@app.on_event("startup")
def load_model_once() -> None:
    global model, loaded_model_version
    if model is not None:
        return

    mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)
    client = MlflowClient(tracking_uri=MLFLOW_TRACKING_URI)
    if MODEL_VERSION:
        model_info = client.get_model_version(MODEL_NAME, MODEL_VERSION)
        model_uri = f"models:/{MODEL_NAME}/{MODEL_VERSION}"
    else:
        model_info = client.get_model_version_by_alias(MODEL_NAME, MODEL_ALIAS)
        model_uri = f"models:/{MODEL_NAME}@{MODEL_ALIAS}"

    model = mlflow.pyfunc.load_model(model_uri)
    loaded_model_version = str(model_info.version)
    print(
        f"Loaded MLflow model uri={model_uri} version={loaded_model_version} "
        f"tracking_uri={MLFLOW_TRACKING_URI}"
    )


@app.get("/v1/models/taxi-duration")
def ready() -> dict:
    if model is None:
        raise HTTPException(status_code=503, detail="model not loaded")
    return {
        "name": "taxi-duration",
        "ready": True,
        "model_name": MODEL_NAME,
        "model_alias": MODEL_ALIAS,
        "model_version": loaded_model_version,
    }


@app.post("/v1/models/taxi-duration:predict")
def predict(trip: TaxiTrip) -> dict:
    if model is None:
        raise HTTPException(status_code=503, detail="model not loaded")
    started = time.perf_counter()
    row = pd.DataFrame(
        [{feature: getattr(trip, feature) for feature in FEATURES}],
        columns=FEATURES,
    )
    prediction = max(0.0, float(model.predict(row)[0]))
    return {
        "predicted_duration": prediction,
        "model_alias": MODEL_ALIAS,
        "model_version": loaded_model_version,
        "latency_ms": round((time.perf_counter() - started) * 1000, 3),
    }
