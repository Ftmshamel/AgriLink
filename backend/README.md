# AgriLink AI Service

A FastAPI app that powers AgriLink's AI features:

- `POST /forecast` — predict harvest dates from crop, planting date, and region
- `POST /price-trend` — classify a price history as rising/falling/stable and forecast next month
- `GET  /crops` — supported crop catalog
- `GET  /regions` — supported regions
- `GET  /health` — liveness probe + dataset stats

## Quick start

```bash
# 1. Create and activate a virtualenv (Windows PowerShell)
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# (macOS / Linux)
# python3 -m venv .venv
# source .venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Run dev server (auto-reload)
uvicorn app.main:app --reload --port 8000
```

The first run automatically generates `data/harvests.csv` and `data/prices.csv`
if they're missing, then trains the ML models on them. To regenerate the data
explicitly:

```bash
python -m scripts.generate_data
```

## Firestore seeding

To upload sample farmers, buyers, and orders into your Firebase Firestore:

1. Place your Firebase service account JSON file on this machine.
2. Install packages (inside the backend virtualenv):

```powershell
pip install -r requirements.txt
```

3. Run the seeder script (replace with your service account path and project id):

```powershell
python -m scripts.seed_firestore --service-account C:\path\to\serviceAccount.json --project-id your-firebase-project-id
```

The script will write documents into `farmers`, `buyers`, and `orders` collections using the sample files in `backend/data`.

## How the model works

### Harvest forecasting (`HarvestForecaster`)

A single `RandomForestRegressor` (`n_estimators=200`, `max_depth=8`) is trained
on `data/harvests.csv` (~1,200 records spanning 20 crops × 5 regions × 2022–2026).

Features:

- one-hot **month-of-year** the crop was planted
- one-hot **region** (Luzon-North/Central/South, Visayas, Mindanao)
- numeric **crop's known average growing period** (so a single forest model
  can generalise across many crops)

Target: **growth days** (date_harvested − date_planted)

Confidence is computed from the model's measured MAE on a held-out 20% split.

### Price trend (`PriceTrender`)

For each crop we train a `LinearRegression` on `data/prices.csv` with features:

- numeric **month-index** since the start of the dataset (long-term trend)
- one-hot **month-of-year** (seasonality)

The trend label (rising/falling/stable) comes from the user-supplied recent
history so the UI matches what the user sees, while the next-month price
forecast comes from the trained model — i.e. real long-term context.

## Replacing with your own data

Swap in any CSV that has these columns and the ML layer will pick it up at
startup:

`data/harvests.csv`:

```
crop,region,date_planted,date_harvested,growth_days,yield_kg,month_planted
```

`data/prices.csv`:

```
crop,region,month,price_php_per_kg
```

Delete or move the existing files and restart the server — they will not be
regenerated if you provide your own.

## Example calls

```bash
curl -X POST http://localhost:8000/forecast \
  -H "Content-Type: application/json" \
  -d '{"crop":"Tomato","date_planted":"2026-04-15","region":"Luzon-Central"}'

curl -X POST http://localhost:8000/price-trend \
  -H "Content-Type: application/json" \
  -d '{"crop":"Tomato","history":[
    {"month":"2025-12","price":50},
    {"month":"2026-01","price":55},
    {"month":"2026-02","price":58},
    {"month":"2026-03","price":62},
    {"month":"2026-04","price":60}
  ]}'
```
