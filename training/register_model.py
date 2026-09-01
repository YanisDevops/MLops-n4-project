import argparse

import mlflow
from mlflow import MlflowClient


def main() -> None:
    parser = argparse.ArgumentParser(description="Register an existing MLflow run model and assign an alias")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--name", default="TaxiDurationXGB")
    parser.add_argument("--alias", default="candidate", choices=["candidate", "champion"])
    args = parser.parse_args()
    result = mlflow.register_model(f"runs:/{args.run_id}/model", args.name)
    MlflowClient().set_registered_model_alias(args.name, args.alias, result.version)
    print(f"{args.name}@{args.alias} -> version {result.version}")


if __name__ == "__main__":
    main()
