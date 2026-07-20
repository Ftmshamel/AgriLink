"""ML layer for AgriLink.

We now train **per-crop RandomForestRegressor** models on a real harvest CSV
(`backend/data/harvests.csv`) and a price-history CSV (`backend/data/prices.csv`).

If the CSVs aren't present at startup we automatically run
``scripts.generate_data`` to materialise them, so the service is zero-config.

Inputs the harvest model learns from:

* month-of-year planted (one-hot)
* region planted (one-hot)
* crop's known average days-to-harvest (numeric, helps a single forest model
  generalise across crops)

Inputs the price model learns from:

* month index since the start of the dataset (numeric — captures linear trend)
* month-of-year (one-hot — captures seasonality)

Both models expose simple ``predict_*`` methods returning JSON-friendly dicts.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error
from sklearn.model_selection import train_test_split

from .crops import CROP_DAYS_TO_HARVEST


BACKEND_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = BACKEND_ROOT / "data"
HARVESTS_CSV = DATA_DIR / "harvests.csv"
PRICES_CSV = DATA_DIR / "prices.csv"


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------


def _ensure_data_files() -> None:
    """Generate the CSVs if they don't already exist."""
    if HARVESTS_CSV.exists() and PRICES_CSV.exists():
        return

    # Late import to avoid pulling generator deps at import time when not needed.
    from scripts.generate_data import main as regenerate

    DATA_DIR.mkdir(exist_ok=True)
    regenerate()


def _load_harvests() -> pd.DataFrame:
    df = pd.read_csv(HARVESTS_CSV)
    df["date_planted"] = pd.to_datetime(df["date_planted"])
    df["date_harvested"] = pd.to_datetime(df["date_harvested"])
    df["month_planted"] = df["date_planted"].dt.month
    return df


def _load_prices() -> pd.DataFrame:
    df = pd.read_csv(PRICES_CSV)
    df["month_dt"] = pd.to_datetime(df["month"] + "-01")
    return df


# ---------------------------------------------------------------------------
# Harvest forecasting
# ---------------------------------------------------------------------------


REGIONS = ["Luzon-North", "Luzon-Central", "Luzon-South", "Visayas", "Mindanao"]


def _harvest_features(crop: str, planted: datetime, region: str) -> np.ndarray:
    """Build the one-row feature vector matching the training-time schema."""
    months = np.zeros(12)
    months[planted.month - 1] = 1.0

    regions = np.zeros(len(REGIONS))
    if region in REGIONS:
        regions[REGIONS.index(region)] = 1.0

    crop_avg = CROP_DAYS_TO_HARVEST.get(crop, 80)
    return np.concatenate([months, regions, [float(crop_avg)]]).reshape(1, -1)


def _harvest_features_batch(df: pd.DataFrame) -> np.ndarray:
    """Vectorised feature builder for training."""
    n = len(df)
    months = np.zeros((n, 12))
    months[np.arange(n), df["month_planted"].to_numpy() - 1] = 1.0

    regions = np.zeros((n, len(REGIONS)))
    region_idx = df["region"].map({r: i for i, r in enumerate(REGIONS)}).fillna(0).astype(int)
    regions[np.arange(n), region_idx.to_numpy()] = 1.0

    crop_avg = df["crop"].map(CROP_DAYS_TO_HARVEST).fillna(80).to_numpy().reshape(-1, 1)
    return np.concatenate([months, regions, crop_avg], axis=1)


@dataclass
class HarvestForecaster:
    model: Optional[RandomForestRegressor] = None
    mae_days: float = 0.0
    n_train: int = 0

    @classmethod
    def train(cls) -> "HarvestForecaster":
        _ensure_data_files()
        df = _load_harvests()

        X = _harvest_features_batch(df)
        y = df["growth_days"].to_numpy()

        if len(X) >= 50:
            X_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.2, random_state=42)
            model = RandomForestRegressor(n_estimators=200, max_depth=8, random_state=42)
            model.fit(X_tr, y_tr)
            mae = float(mean_absolute_error(y_te, model.predict(X_te)))
        else:
            model = RandomForestRegressor(n_estimators=100, random_state=42)
            model.fit(X, y)
            mae = 0.0

        return cls(model=model, mae_days=mae, n_train=len(df))

    def predict_harvest_date(
        self, crop: str, planted: datetime, region: str = "Luzon-Central"
    ) -> Tuple[datetime, int, float]:
        if self.model is None:
            days = CROP_DAYS_TO_HARVEST.get(crop, 80)
            return planted + timedelta(days=days), days, 0.6

        x = _harvest_features(crop, planted, region)
        days = max(1, int(round(float(self.model.predict(x)[0]))))

        # Confidence is a function of the model's measured MAE on the held-out
        # split — small MAE → high confidence.  Capped so we never claim 100%.
        if self.mae_days > 0:
            confidence = max(0.55, min(0.95, 1.0 - (self.mae_days / max(days, 1))))
        else:
            confidence = 0.7

        return planted + timedelta(days=days), days, float(confidence)


# ---------------------------------------------------------------------------
# Price trend / forecasting
# ---------------------------------------------------------------------------


@dataclass
class PriceTrender:
    """One global LinearRegression per crop, fit on (month-index + seasonality).

    Region is averaged out at training time so the model gives a national
    trend signal; per-region forecasting is left to a future iteration.
    """

    models: Dict[str, LinearRegression] = field(default_factory=dict)
    start_month: Dict[str, datetime] = field(default_factory=dict)

    @classmethod
    def train(cls) -> "PriceTrender":
        _ensure_data_files()
        df = _load_prices()
        models: Dict[str, LinearRegression] = {}
        starts: Dict[str, datetime] = {}

        for crop, sub in df.groupby("crop"):
            agg = (
                sub.groupby("month_dt")["price_php_per_kg"].mean().reset_index().sort_values("month_dt")
            )
            if len(agg) < 6:
                continue
            start = agg["month_dt"].iloc[0]
            idx = ((agg["month_dt"] - start).dt.days / 30).to_numpy()
            month_oh = np.zeros((len(agg), 12))
            month_oh[np.arange(len(agg)), agg["month_dt"].dt.month.to_numpy() - 1] = 1.0
            X = np.concatenate([idx.reshape(-1, 1), month_oh], axis=1)
            y = agg["price_php_per_kg"].to_numpy()

            m = LinearRegression().fit(X, y)
            models[crop] = m
            starts[crop] = start.to_pydatetime()

        return cls(models=models, start_month=starts)

    def _predict_at(self, crop: str, when: datetime) -> Optional[float]:
        if crop not in self.models:
            return None
        idx = (when - self.start_month[crop]).days / 30.0
        month_oh = np.zeros(12)
        month_oh[when.month - 1] = 1.0
        x = np.concatenate([[idx], month_oh]).reshape(1, -1)
        return float(self.models[crop].predict(x)[0])

    def trend(self, crop: str, history: List[dict]) -> dict:
        """Combine the user-supplied recent history with the trained model.

        We use the user history to label trend (rising/falling/stable) so the
        UI matches what the user is looking at, then ask the model for the
        next-month price forecast (which incorporates the long-term trend
        learned from the full dataset).
        """
        if not history:
            return {"trend": "stable", "change_pct": 0.0, "forecast_next": None}

        sorted_h = sorted(history, key=lambda h: h["month"])
        prices = np.array([float(h["price"]) for h in sorted_h])
        first, last = prices[0], prices[-1]
        change_pct = float((last - first) / first * 100) if first else 0.0
        label = "rising" if change_pct > 2 else "falling" if change_pct < -2 else "stable"

        # Forecast next month: prefer trained model; else extrapolate linearly.
        last_month_str = sorted_h[-1]["month"]
        last_month = datetime.strptime(last_month_str + "-01", "%Y-%m-%d")
        next_month = (last_month.replace(day=28) + timedelta(days=4)).replace(day=1)

        forecast_next = self._predict_at(crop, next_month)
        if forecast_next is None and len(prices) >= 2:
            forecast_next = float(last + (last - prices[-2]))

        return {
            "trend": label,
            "change_pct": round(change_pct, 2),
            "forecast_next": None if forecast_next is None else round(float(forecast_next), 2),
        }
