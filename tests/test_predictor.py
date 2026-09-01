from fastapi.testclient import TestClient

from src.predictor import app as predictor


class FakeModel:
    def predict(self, rows):
        return [12.5]


# def test_prediction_contract(monkeypatch):
#     monkeypatch.setattr(predictor, "model", FakeModel())
#     with TestClient(predictor.app) as client:
#         response = client.post("/v1/models/taxi-duration:predict", json={
#             "trip_distance": 2.8,
#             "pickup_hour": 8,
#             "pickup_dow": 1,
#             "PULocationID": 161,
#             "DOLocationID": 237,
#         })
#     assert response.status_code == 200
#     body = response.json()
#     assert body["predicted_duration"] == 12.5
#     assert "model_alias" in body
#     assert "latency_ms" in body

def test_prediction_contract(monkeypatch):
    monkeypatch.setattr(predictor, "model", FakeModel())
    monkeypatch.setattr(predictor, "loaded_model_version", "test-version")

    with TestClient(predictor.app) as client:
        response = client.post(
            "/v1/models/taxi-duration:predict",
            json={
                "trip_distance": 2.8,
                "pickup_hour": 8,
                "pickup_dow": 1,
                "PULocationID": 161,
                "DOLocationID": 237,
            },
        )

    assert response.status_code == 200
    body = response.json()
    assert body["predicted_duration"] == 12.5
    assert body["model_version"] == "test-version"
    assert "model_alias" in body
    assert "latency_ms" in body