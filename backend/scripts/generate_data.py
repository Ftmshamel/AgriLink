"""Generate realistic-looking historical CSV datasets for AgriLink.

Two files are produced:

  data/harvests.csv  – per-planting records (crop, region, dates, yield).
  data/prices.csv    – monthly market prices in PHP/kg per crop and region.

The generator is fully deterministic given the seed, so we can ship the
generated CSVs in source control and re-create them on demand.

Why generated?  AgriLink is a teaching scaffold; we want a non-trivial dataset
that drives a realistic regressor without bundling proprietary or copyrighted
data.  Crop growth periods, regions, and seasonal effects are based on
publicly known PH agronomy heuristics.

Run from the backend/ directory:

    python -m scripts.generate_data
"""

from __future__ import annotations

import csv
from datetime import datetime, timedelta
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
DATA_DIR.mkdir(exist_ok=True)

# Average days-to-harvest per crop (PH agronomy heuristics).
CROP_DAYS = {
    "Tomato": 75, "Eggplant": 90, "Lettuce": 45, "Bell Pepper": 80,
    "Cabbage": 70, "Carrot": 90, "Cucumber": 55, "Onion": 120,
    "Garlic": 150, "Corn": 90, "Rice": 120, "Squash": 100,
    "Okra": 55, "String Beans": 60, "Spinach": 40, "Pechay": 30,
    "Sweet Potato": 110, "Cassava": 270, "Ginger": 240,
    "Bitter Gourd (Ampalaya)": 70,
}

# Region: mean PHP / kg (anchor) at "neutral" seasonality.
REGIONS = {
    "Luzon-North":   1.00,   # multiplier on crop's base price
    "Luzon-Central": 0.96,
    "Luzon-South":   1.05,
    "Visayas":       1.08,
    "Mindanao":      0.93,
}

# Anchor mean PHP/kg per crop (very rough, just to make trends realistic).
BASE_PRICE = {
    "Tomato": 55, "Eggplant": 42, "Lettuce": 75, "Bell Pepper": 95,
    "Cabbage": 35, "Carrot": 80, "Cucumber": 38, "Onion": 110,
    "Garlic": 220, "Corn": 25, "Rice": 50, "Squash": 32,
    "Okra": 50, "String Beans": 60, "Spinach": 65, "Pechay": 40,
    "Sweet Potato": 35, "Cassava": 30, "Ginger": 180,
    "Bitter Gourd (Ampalaya)": 65,
}

# Per-month multiplier on growth speed.  Cooler/dry months in PH = slower.
GROWTH_SEASON = np.array(
    [1.05, 1.05, 0.97, 0.95, 0.97, 1.02, 1.03, 1.04, 1.04, 1.03, 1.05, 1.06]
)
# Per-month multiplier on prices (peaks in lean months Aug–Oct).
PRICE_SEASON = np.array(
    [1.00, 1.00, 0.97, 0.96, 0.98, 1.02, 1.05, 1.10, 1.12, 1.08, 1.02, 1.00]
)


def daterange(start: datetime, end: datetime, step_days: int = 1):
    cur = start
    while cur <= end:
        yield cur
        cur += timedelta(days=step_days)


def generate_harvests(seed: int = 42, samples_per_crop: int = 60) -> list[dict]:
    rng = np.random.default_rng(seed)
    rows: list[dict] = []

    start = datetime(2022, 1, 1)
    end = datetime(2026, 4, 1)

    for crop, avg_days in CROP_DAYS.items():
        for _ in range(samples_per_crop):
            # Random planting date within the window
            offset_days = int(rng.integers(0, (end - start).days))
            planted = start + timedelta(days=offset_days)
            region = rng.choice(list(REGIONS.keys()))

            # Per-region growth bias: Mindanao slightly faster, North Luzon slightly slower.
            region_growth = {
                "Luzon-North": 1.04, "Luzon-Central": 1.00,
                "Luzon-South": 1.00, "Visayas": 0.99, "Mindanao": 0.96,
            }[region]

            base = avg_days * GROWTH_SEASON[planted.month - 1] * region_growth
            noise = rng.normal(0, max(2, avg_days * 0.04))
            days = max(1, int(round(base + noise)))
            harvested = planted + timedelta(days=days)

            # Yield (kg) — vary by crop and a touch of regional bias
            base_yield = {
                "Tomato": 1500, "Eggplant": 1100, "Lettuce": 600,
                "Bell Pepper": 800, "Cabbage": 1200, "Carrot": 900,
                "Cucumber": 700, "Onion": 1000, "Garlic": 700,
                "Corn": 4000, "Rice": 4500, "Squash": 1500,
                "Okra": 600, "String Beans": 700, "Spinach": 350,
                "Pechay": 400, "Sweet Potato": 1500, "Cassava": 3500,
                "Ginger": 600, "Bitter Gourd (Ampalaya)": 800,
            }[crop]
            yield_kg = max(50, base_yield * float(rng.normal(1.0, 0.18)))

            rows.append({
                "crop": crop,
                "region": region,
                "date_planted": planted.date().isoformat(),
                "date_harvested": harvested.date().isoformat(),
                "growth_days": days,
                "yield_kg": round(yield_kg, 1),
                "month_planted": planted.month,
            })
    return rows


def generate_prices(seed: int = 7) -> list[dict]:
    """One row per (crop, region, month) over ~4 years."""
    rng = np.random.default_rng(seed)
    rows: list[dict] = []

    start = datetime(2022, 1, 1)
    end = datetime(2026, 4, 1)

    for crop, base in BASE_PRICE.items():
        # Long-term per-crop trend — small annual % change in either direction.
        annual_drift = rng.normal(0.04, 0.04)  # +4%/yr ± 4%

        cur = start.replace(day=1)
        while cur <= end:
            for region, region_mult in REGIONS.items():
                years_in = (cur - start).days / 365.0
                trend_mult = (1 + annual_drift) ** years_in
                season = PRICE_SEASON[cur.month - 1]
                noise = float(rng.normal(1.0, 0.05))

                price = base * region_mult * trend_mult * season * noise
                rows.append({
                    "crop": crop,
                    "region": region,
                    "month": cur.strftime("%Y-%m"),
                    "price_php_per_kg": round(price, 2),
                })
            # Next month
            year = cur.year + (1 if cur.month == 12 else 0)
            month = 1 if cur.month == 12 else cur.month + 1
            cur = cur.replace(year=year, month=month)
    return rows


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)


def main():
    harvests = generate_harvests()
    prices = generate_prices()
    write_csv(DATA_DIR / "harvests.csv", harvests)
    write_csv(DATA_DIR / "prices.csv", prices)
    print(f"Wrote {len(harvests):,} harvest rows  -> {DATA_DIR / 'harvests.csv'}")
    print(f"Wrote {len(prices):,} price   rows  -> {DATA_DIR / 'prices.csv'}")


if __name__ == "__main__":
    main()
