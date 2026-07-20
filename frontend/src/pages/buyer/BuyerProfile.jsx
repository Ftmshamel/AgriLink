import { useState } from "react";
import { Save, User, Phone, Building2, MapPin, BadgeCheck } from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import ImageUpload from "../../components/ui/ImageUpload";

export default function BuyerProfile() {
  const { user, updateProfile } = useAuth();
  const [form, setForm] = useState({
    name:         user.name || "",
    phone:        user.phone || "",
    businessType: user.businessType || "Restaurant",
    address:      user.address || "",
    photo:        user.photo || null,
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
      setError(err?.message || "Unable to save profile. Please try a smaller photo.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={submit} className="flex-1 flex flex-col space-y-6">
      <div className="border-l-4 border-harvest-500 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">Buyer Profile</h1>
        <p className="text-sm text-slate-500">Keep your business details up to date.</p>
      </div>

      <div className="flex-1 grid lg:grid-cols-3 gap-6">
        {/* Left: account summary card */}
        <div className="lg:col-span-1 flex flex-col gap-4">
          <div className="card-harvest flex flex-col items-center p-8 text-center gap-3">
            <div>
              <p className="font-extrabold text-slate-900 text-lg">{user.name}</p>
              <p className="text-sm text-slate-500">{user.email}</p>
            </div>
            <span className="badge-amber font-bold flex items-center gap-1">
              <Building2 size={12} /> {user.businessType || "Buyer"}
            </span>
            {user.verified && (
              <span className="badge-green flex items-center gap-1">
                <BadgeCheck size={12} /> Verified account
              </span>
            )}
            <div className="w-full pt-3 text-left">
              <ImageUpload
                label="Profile photo"
                folder="profiles"
                aspect="aspect-square"
                value={form.photo}
                maxDim={520}
                quality={0.72}
                onBusyChange={setPhotoBusy}
                onChange={(photo) => set({ photo })}
              />
            </div>
          </div>

          <div className="card p-5 space-y-3">
            <p className="text-xs font-bold uppercase tracking-widest text-slate-400">Account info</p>
            <div className="flex items-center gap-3 text-sm">
              <div className="grid h-8 w-8 place-items-center rounded-lg bg-slate-100 text-slate-500">
                <User size={14} />
              </div>
              <div>
                <p className="text-xs text-slate-400">Name</p>
                <p className="font-semibold text-slate-800">{user.name || "—"}</p>
              </div>
            </div>
            <div className="flex items-center gap-3 text-sm">
              <div className="grid h-8 w-8 place-items-center rounded-lg bg-slate-100 text-slate-500">
                <Phone size={14} />
              </div>
              <div>
                <p className="text-xs text-slate-400">Phone</p>
                <p className="font-semibold text-slate-800">{user.phone || "—"}</p>
              </div>
            </div>
            <div className="flex items-center gap-3 text-sm">
              <div className="grid h-8 w-8 place-items-center rounded-lg bg-slate-100 text-slate-500">
                <MapPin size={14} />
              </div>
              <div>
                <p className="text-xs text-slate-400">Address</p>
                <p className="font-semibold text-slate-800">{user.address || "—"}</p>
              </div>
            </div>
          </div>
        </div>

        {/* Right: edit form */}
        <section className="card-accent lg:col-span-2 flex flex-col">
          <div className="border-b-2 border-slate-100 px-6 py-4">
            <h2 className="font-extrabold text-slate-900">Edit Details</h2>
            <p className="text-xs text-slate-500">Changes are saved to your account immediately.</p>
          </div>

          <div className="flex-1 p-6 space-y-5">
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <label className="label">Business name</label>
                <input className="input" value={form.name} onChange={(e) => set({ name: e.target.value })} required />
              </div>
              <div>
                <label className="label">Business type</label>
                <select className="input" value={form.businessType} onChange={(e) => set({ businessType: e.target.value })}>
                  <option>Restaurant</option>
                  <option>Wholesaler</option>
                  <option>Hotel</option>
                  <option>Supermarket</option>
                  <option>Other</option>
                </select>
              </div>
              <div>
                <label className="label">Phone</label>
                <input className="input" value={form.phone} onChange={(e) => set({ phone: e.target.value })} placeholder="+63 9XX XXX XXXX" />
              </div>
              <div>
                <label className="label">Business address</label>
                <input className="input" value={form.address} onChange={(e) => set({ address: e.target.value })} placeholder="City, Province" />
              </div>
            </div>

            {/* Filler to push button to bottom */}
            <div className="flex-1" />
          </div>

          <div className="border-t-2 border-slate-100 px-6 py-4 flex items-center justify-between">
            {error
              ? <span className="text-sm font-semibold text-rose-600">{error}</span>
              : photoBusy
                ? <span className="text-sm font-semibold text-slate-500">Uploading photo...</span>
                : saved
              ? <span className="flex items-center gap-1.5 text-sm font-semibold text-brand-700"><BadgeCheck size={15} /> Profile updated!</span>
              : <span />
            }
            <button type="submit" className="btn-primary px-6 py-2.5" disabled={saving || photoBusy}>
              <Save size={16} /> {saving ? "Saving..." : "Save changes"}
            </button>
          </div>
        </section>
      </div>
    </form>
  );
}
