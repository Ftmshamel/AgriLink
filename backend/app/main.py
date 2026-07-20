"""AgriLink AI service — FastAPI entry point.

Routes:
  GET  /health         — service liveness check + dataset stats
  GET  /crops          — supported crop catalog
  GET  /regions        — supported regions for harvest predictions
  POST /forecast       — predict harvest date from crop + planting date + region
  POST /price-trend    — classify price trend + forecast next month
"""

from __future__ import annotations

from datetime import date, datetime
from typing import List, Optional

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .crops import CROP_DAYS_TO_HARVEST, add_custom_crop, get_crop_days_to_harvest
from .ml import HarvestForecaster, PriceTrender, REGIONS


# --------------------------- App setup --------------------------- #

app = FastAPI(
    title="AgriLink AI Service",
    version="0.2.0",
    description="Smart-forecasting backend for the AgriLink agricultural supply chain platform.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Train models on startup. They're cheap to fit and easy to keep in memory.
forecaster: HarvestForecaster = HarvestForecaster.train()
price_trender: PriceTrender = PriceTrender.train()


# --------------------------- Schemas --------------------------- #


class ForecastRequest(BaseModel):
    crop: str = Field(..., examples=["Tomato"])
    date_planted: date = Field(..., description="ISO date the crop was planted")
    region: Optional[str] = Field("Luzon-Central", description="Region of the farm")


class ForecastResponse(BaseModel):
    crop: str
    date_planted: date
    region: str
    growth_days: int
    estimated_harvest_date: date
    confidence: float
    source: str = "model"


class PriceHistoryItem(BaseModel):
    month: str = Field(..., description="YYYY-MM")
    price: float


class PriceTrendRequest(BaseModel):
    crop: str
    history: List[PriceHistoryItem]


class PriceTrendResponse(BaseModel):
    crop: str
    trend: str
    change_pct: float
    forecast_next: Optional[float]
    source: str = "model"


class CropCreateRequest(BaseModel):
    name: str = Field(..., min_length=1)
    avg_days_to_harvest: int = Field(..., ge=1, le=1000)


# --------------------------- Routes --------------------------- #


@app.get("/health")
def health():
    crop_catalog = get_crop_days_to_harvest()
    return {
        "ok": True,
        "service": "agrilink-ai",
        "supported_crops": len(crop_catalog),
        "harvest_model": {
            "n_train": forecaster.n_train,
            "mae_days": round(forecaster.mae_days, 2),
        },
        "price_model": {
            "crops_trained": len(price_trender.models),
        },
    }


@app.get("/crops")
def crops():
    return {
        "crops": [
            {"name": name, "avg_days_to_harvest": days}
            for name, days in sorted(get_crop_days_to_harvest().items())
        ]
    }


@app.post("/crops")
def add_crop(req: CropCreateRequest):
    catalog = add_custom_crop(req.name, req.avg_days_to_harvest)
    return {
        "ok": True,
        "crop": {"name": req.name.strip(), "avg_days_to_harvest": int(req.avg_days_to_harvest)},
        "supported_crops": len(catalog),
    }


@app.get("/regions")
def regions():
    return {"regions": REGIONS}


@app.post("/forecast", response_model=ForecastResponse)
def forecast(req: ForecastRequest):
    planted_dt = datetime.combine(req.date_planted, datetime.min.time())
    region = req.region or "Luzon-Central"
    harvest, days, confidence = forecaster.predict_harvest_date(req.crop, planted_dt, region)
    return ForecastResponse(
        crop=req.crop,
        date_planted=req.date_planted,
        region=region,
        growth_days=days,
        estimated_harvest_date=harvest.date(),
        confidence=round(confidence, 2),
    )


@app.post("/price-trend", response_model=PriceTrendResponse)
def price_trend(req: PriceTrendRequest):
    result = price_trender.trend(req.crop, [h.model_dump() for h in req.history])
    return PriceTrendResponse(
        crop=req.crop,
        trend=result["trend"],
        change_pct=result["change_pct"],
        forecast_next=result["forecast_next"],
    )
