import os

import mlflow
import mlflow.xgboost
import numpy as np
import pandas as pd
from mlflow import MlflowClient
from sklearn.metrics import mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from xgboost import XGBRegressor

FEATURES = ["trip_distance", "pickup_hour", "pickup_dow", "PULocationID", "DOLocationID"]
TARGET = "duration"


def load_data() -> pd.DataFrame:
    data_path = os.getenv("TRAINING_DATA")
    if data_path:
        return pd.read_parquet(data_path)
    rng = np.random.default_rng(42)
    rows = 2500
    distance = rng.gamma(2.0, 2.0, rows)
    hour = rng.integers(0, 24, rows)
    frame = pd.DataFrame({
        "trip_distance": distance,
        "pickup_hour": hour,
        "pickup_dow": rng.integers(0, 7, rows),
        "PULocationID": rng.integers(1, 264, rows),
        "DOLocationID": rng.integers(1, 264, rows),
    })
    rush_hour = np.isin(hour, [7, 8, 9, 16, 17, 18])
    frame[TARGET] = 4.5 + distance * 3.1 + (rush_hour * 4) + rng.normal(0, 2, rows)
    return frame


def main() -> None:
    tracking_uri = os.getenv("MLFLOW_TRACKING_URI", "http://127.0.0.1:5000")
    model_name = os.getenv("MLFLOW_MODEL_NAME", "TaxiDurationXGB")
    alias = os.getenv("MODEL_ALIAS", "candidate")
    experiment_name = os.getenv("MLFLOW_EXPERIMENT_NAME", "nyc-taxi-duration-proxied")
    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment(experiment_name)

    data = load_data().dropna(subset=FEATURES + [TARGET])
    train_x, test_x, train_y, test_y = train_test_split(data[FEATURES], data[TARGET], test_size=0.2, random_state=42)
    params = {"n_estimators": 150, "max_depth": 6, "learning_rate": 0.08, "subsample": 0.9, "random_state": 42}

    with mlflow.start_run() as run:
        model = XGBRegressor(**params)
        model.fit(train_x, train_y)
        predictions = model.predict(test_x)
        rmse = float(mean_squared_error(test_y, predictions, squared=False))
        r2 = float(r2_score(test_y, predictions))
        mlflow.log_params(params)
        mlflow.log_metrics({"rmse": rmse, "r2": r2})
        result = mlflow.xgboost.log_model(
            model,
            artifact_path="model",
            registered_model_name=model_name,
            input_example=train_x.head(3),
        )
        version = result.registered_model_version
        MlflowClient().set_registered_model_alias(model_name, alias, version)
        print(
            f"run_id={run.info.run_id} model={model_name} version={version} "
            f"alias={alias} experiment={experiment_name} rmse={rmse:.3f} r2={r2:.3f}"
        )


if __name__ == "__main__":
    main()
