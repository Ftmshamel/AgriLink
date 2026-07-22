# AgriLink — AI-Powered Agricultural Supply Chain

## Mobile app

The [`mobile`](mobile/) Flutter project contains the Consumer and Rider
experiences, including account creation and persistent sign-in. Farmer and
Superadmin remain in the existing web frontend.

Marketplace and delivery content currently uses seed data while the shared
cloud backend is being configured.

AgriLink connects Filipino farmers directly with bulk buyers (restaurants,
wholesalers, hotels). It cuts out middlemen with three pillars:

- **AI harvest forecasting** trained on real CSV harvest data
- **Real-time order tracking** — Shopee-style status pipeline with live updates
- **Map-pinned logistics** — every farm has a saved pickup hub
- **Photos + payments** — crop / farm photos, downpayment & balance flow

## Stack

| Layer         | Tech                                                          |
| ------------- | ------------------------------------------------------------- |
| Frontend      | React 19 + Vite + Tailwind CSS + React Router                 |
| Charts / Maps | Recharts, React-Leaflet (OpenStreetMap)                       |
| AI Backend    | Python 3.10+ • FastAPI • Scikit-learn (RandomForest) • Pandas |
| Realtime DB   | Firebase Firestore (with localStorage fallback)               |
| Storage       | Firebase Storage (with data-URL fallback)                     |
| Auth          | Custom users collection (Firebase Auth migration TODO)        |

## Repo layout

```
agrilinks/
├── frontend/      # React + Vite app
├── backend/       # Python FastAPI service for AI forecasts
└── README.md      # this file
```

## Quick start

### 1) Backend (Python AI service)

```bash
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1     # Windows
# source .venv/bin/activate      # macOS / Linux

pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

On first run the backend auto-generates `data/harvests.csv` and `data/prices.csv`
(~1,200 + ~5,000 rows respectively) and trains a per-feature `RandomForestRegressor`
on the harvest data plus a per-crop `LinearRegression` on the price data.

`GET /health` reports the dataset size and the harvest model's MAE on a held-out 20%.

### 2) Frontend

```bash
cd frontend
npm install
copy .env.example .env   # or cp; fill in Firebase keys
npm run dev              # http://localhost:5173
```

The app works **without** any external services — it falls back to a localStorage-
backed mock DB and a client-side forecast when neither Firebase nor the Python
backend is available.

### 3) First account setup

Use the registration flow in the app to create your first farmer or buyer account:

1. Open `http://localhost:5173`
2. Click **Create an account**
3. Complete Step 1 and Step 2 of onboarding

Admin accounts are intended to be provisioned by the internal team.

## Enabling real Firebase

Fill in `frontend/.env`:

```
VITE_FIREBASE_API_KEY=...
VITE_FIREBASE_AUTH_DOMAIN=<project-id>.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=<project-id>
VITE_FIREBASE_STORAGE_BUCKET=<project-id>.firebasestorage.app
VITE_FIREBASE_MSG_SENDER_ID=<project-number>
VITE_FIREBASE_APP_ID=1:<project-number>:web:...
```

The two values you must fetch from the Firebase Console (Project Settings →
Your apps → Web app) are `apiKey` and `appId`. The rest are derived from
your project ID and project number.

When all six are present, the app automatically:

- Reads / writes to Firestore (`users`, `plantings`, `orders`, `marketPrices`)
- Subscribes to live updates via `onSnapshot`
- Uploads crop / farm photos to Firebase Storage and stores their download URLs
- Bypasses the localStorage demo

You'll also want to set the following Firestore security rules early on (basic
ownership-based read/write, tighten later as needed):

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == uid;
    }
    match /plantings/{id} {
      allow read: if true;
      allow create, update, delete: if request.auth != null;
    }
    match /orders/{id} {
      allow read: if request.auth != null;
      allow create, update: if request.auth != null;
    }
    match /marketPrices/{id} {
      allow read: if true;
      allow write: if request.auth != null;
    }
  }
}
```

## Roles & features

### Farmer (Producer)

- AI harvest forecast (crop + planting date + region → estimated harvest)
- Real-time dashboard with planting status, yield, grade, days-to-harvest
- Order management — Pending → Growing → Preparing → Ready → In Transit → Delivered
- Map-pinned saved location (default pickup / delivery hub)
- Farm photo upload (Firebase Storage)
- Crop photo upload per planting

### Buyer (Consumer)

- Upcoming Harvest Marketplace with crop photos and farm avatars
- AI Price Trend chart + next-month forecast (Recharts)
- **Pre-ordering with payment flow**:
  - Choose payment mode (full / 50% / 30% downpayment / COD)
  - Choose method (GCash, Maya, BPI, BDO, UnionBank, Cash)
  - Confirmation step before charging
- Real-time progress tracker
- Pay remaining balance later from order details
- Map view of every farm location

### Admin (Moderator)

- Verify farmers and buyers (with farm photos visible)
- Add / manage market price entries that drive AI trends
- Transaction monitoring with payment status filter
- System health dashboard

## Architecture notes

### Data layer (`frontend/src/services/db.js`)

A unified `db` object is exported. At runtime it points to either:

- `firestoreDb.js` — when Firebase is configured. Subscribes to all four
  collections via `onSnapshot`, caches them in memory, and exposes
  synchronous reads + async writes.
- `mockDb.js` — localStorage-backed seed data with the same surface.

Both are interchangeable — the rest of the app doesn't know which is active.

### Storage layer (`frontend/src/services/storage.js`)

The `uploadImage(file, folder)` function:

1. Resizes the image client-side (max 1280px, JPEG q=82).
2. If Firebase Storage is configured, uploads the resized blob and returns
   `{ url, path, kind: 'firebase' }`.
3. Otherwise returns `{ url: <data URL>, path: null, kind: 'data-url' }`.

Documents store the returned record verbatim, so the UI doesn't care
where the bytes live.

### ML layer (`backend/app/ml.py`)

`HarvestForecaster.train()` fits a `RandomForestRegressor(n_estimators=200,
max_depth=8)` on the synthesised harvests CSV with one-hot month,
one-hot region, and the crop's known average days-to-harvest as
features. Confidence is derived from the model's MAE on a 20% held-out
split.

`PriceTrender.train()` fits a per-crop `LinearRegression` on
(month-index + one-hot month) features for the prices CSV. The next-month
forecast comes from this model; the trend label (rising/falling/stable)
comes from the user-supplied recent history so the UI matches the chart.

To plug in your own dataset, drop a CSV with the same columns into
`backend/data/` and restart — the auto-generation step is skipped if a
file already exists.

## Scripts cheat-sheet

```bash
# Frontend
npm run dev       # start Vite dev server
npm run build     # production build
npm run preview   # serve the production build
npm run lint      # ESLint

# Backend
uvicorn app.main:app --reload --port 8000   # dev
uvicorn app.main:app --port 8000            # prod
python -m scripts.generate_data             # regenerate CSVs explicitly
```

## Deployment

The system is split into two deployable parts:

- Frontend: deploy `frontend/` to Vercel
- Backend: deploy `backend/` to Render or another Python host

### Frontend on Vercel

1. Create a Vercel project from the `frontend/` folder.
2. Set the build command to `npm run build`.
3. Set the output directory to `dist`.
4. Add `VITE_API_URL` in Vercel environment variables and point it at your backend URL.

The app includes `frontend/vercel.json` so Vercel serves the React router correctly.

### Backend on Render

1. Create a new Render Web Service from the repo.
2. Use the `backend/render.yaml` service definition, or set:

- Build command: `pip install -r requirements.txt`
- Start command: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`

3. After deploy, copy the backend URL into Vercel as `VITE_API_URL`.

### Example flow

1. Deploy backend first.
2. Copy the backend public URL.
3. Set that URL as `VITE_API_URL` in Vercel.
4. Redeploy the frontend.
