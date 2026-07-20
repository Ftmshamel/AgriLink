# AgriLink Frontend

React 19 + Vite + Tailwind CSS application.

```bash
npm install
npm run dev      # http://localhost:5173
npm run build
npm run preview
npm run lint
```

Set `VITE_API_URL` in `.env` to point at the Python backend (defaults to
`http://localhost:8000`). When running the backend isn't required — the
app falls back to a deterministic client-side forecast.

See the root `README.md` for the full setup, role overview, and how to
plug in real Firebase credentials.
