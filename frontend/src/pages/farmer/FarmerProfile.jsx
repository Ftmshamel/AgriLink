import { useState } from "react";
import { Save, MapPin } from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import MapPicker from "../../components/map/MapPicker";
import ImageUpload from "../../components/ui/ImageUpload";

const REGIONS = [
  "Luzon-North",
  "Luzon-Central",
  "Luzon-South",
  "Visayas",
  "Mindanao",
];

export default function FarmerProfile() {
  const { user, updateProfile } = useAuth();
  const [form, setForm] = useState({
    name: user.name || "",
    phone: user.phone || "",
    farmName: user.farmName || "",
    barangay: user.barangay || "",
    municipality: user.municipality || "",
    province: user.province || "",
    region: user.region || "Luzon-Central",
    location: user.location || null,
    photo: user.photo || null,
  });
  const [saved, setSaved] = useState(false);
  const [saving, setSaving] = useState(false);
  const [photoBusy, setPhotoBusy] = useState(false);
  const [error, setError] = useState("");

  const set = (patch) => {
    setSaved(false);
    setError("");
    setForm((f) => ({ ...f, ...patch }));
  };

  const submit = async (e) => {
    e.preventDefault();
    if (photoBusy) return;
    setSaving(true);
    setError("");
    try {
      await updateProfile(form);
      setSaved(true);
    } catch (err) {
      setError(
        err?.message || "Unable to save profile. Please try a smaller photo.",
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={submit} className="flex-1 flex flex-col space-y-6">
      <div>
        <h1 className="font-display text-2xl font-bold text-slate-900">
          Farm Profile
        </h1>
        <p className="text-sm text-slate-500">
          Your saved location is the default pickup &amp; delivery hub for
          buyers.
        </p>
      </div>

      <section className="card p-6 grid lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1">
          <ImageUpload
            label="Farm photo"
            folder="farms"
            aspect="aspect-square"
            value={form.photo}
            maxDim={520}
            quality={0.72}
            onBusyChange={setPhotoBusy}
            onChange={(photo) => set({ photo })}
          />
        </div>

        <div className="lg:col-span-2 grid sm:grid-cols-2 gap-4">
          <div>
            <label className="label">Full name</label>
            <input
              className="input"
              value={form.name}
              onChange={(e) => set({ name: e.target.value })}
              required
            />
          </div>
          <div>
            <label className="label">Phone</label>
            <input
              className="input"
              value={form.phone}
              onChange={(e) => set({ phone: e.target.value })}
            />
          </div>
          <div>
            <label className="label">Farm name</label>
            <input
              className="input"
              value={form.farmName}
              onChange={(e) => set({ farmName: e.target.value })}
            />
          </div>
          <div>
            <label className="label">Region (used by AI forecasts)</label>
            <select
              className="input"
              value={form.region}
              onChange={(e) => set({ region: e.target.value })}
            >
              {REGIONS.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="label">Barangay</label>
            <input
              className="input"
              value={form.barangay}
              onChange={(e) => set({ barangay: e.target.value })}
            />
          </div>
          <div>
            <label className="label">Municipality / City</label>
            <input
              className="input"
              value={form.municipality}
              onChange={(e) => set({ municipality: e.target.value })}
            />
          </div>
          <div className="sm:col-span-2">
            <label className="label">Province</label>
            <input
              className="input"
              value={form.province}
              onChange={(e) => set({ province: e.target.value })}
            />
          </div>
        </div>
      </section>

      <section className="card p-6 flex-1 flex flex-col">
        <label className="label flex items-center gap-2">
          <MapPin size={14} /> Saved farm location
        </label>
        <p className="text-xs text-slate-500 mb-3">
          Click anywhere on the map to update your pin.
        </p>
        <div className="flex-1 min-h-[300px]">
          <MapPicker
            value={form.location}
            onChange={(loc) =>
              set({
                location: loc,
                barangay: loc?.barangay || form.barangay,
                municipality: loc?.municipality || form.municipality,
                province: loc?.province || form.province,
              })
            }
            height="100%"
          />
        </div>
        {form.location && (
          <div className="mt-2 text-xs text-slate-500">
            Pinned: {form.location.lat.toFixed(5)},{" "}
            {form.location.lng.toFixed(5)}
          </div>
        )}
      </section>

      <div className="flex items-center justify-between">
        <div>
          {error && <span className="text-sm text-rose-600">{error}</span>}
          {!error && saved && (
            <span className="text-sm text-brand-700">Profile updated</span>
          )}
          {!error && !saved && photoBusy && (
            <span className="text-sm text-slate-500">Uploading photo...</span>
          )}
        </div>
        <button
          type="submit"
          className="btn-primary"
          disabled={saving || photoBusy}
        >
          <Save size={16} /> {saving ? "Saving..." : "Save changes"}
        </button>
      </div>
    </form>
  );
}
