import { useState } from "react";
import { BadgeCheck, Mail, Save, ShieldCheck, User } from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import Avatar from "../../components/ui/Avatar";
import ImageUpload from "../../components/ui/ImageUpload";

export default function AdminProfile() {
  const { user, updateProfile } = useAuth();
  const [form, setForm] = useState({
    name: user.name || "",
    phone: user.phone || "",
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
      setError(err?.message || "Unable to save profile. Please try a smaller photo.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={submit} className="flex-1 flex flex-col space-y-6">
      <div className="border-l-4 border-brand-600 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">Admin Profile</h1>
        <p className="text-sm text-slate-500">Update your admin account details and profile photo.</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <section className="card p-6 flex flex-col items-center gap-4 text-center">
          <Avatar
            user={{ ...user, name: form.name, photo: form.photo }}
            className="h-24 w-24 rounded-2xl shadow-soft"
            textClassName="text-4xl"
          />
          <div>
            <p className="text-lg font-extrabold text-slate-900">{form.name || user.email}</p>
            <p className="text-sm text-slate-500">{user.email}</p>
          </div>
          <span className="badge-green flex items-center gap-1">
            <ShieldCheck size={12} /> Administrator
          </span>

          <div className="w-full pt-2 text-left">
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
        </section>

        <section className="card-accent lg:col-span-2 flex flex-col">
          <div className="border-b-2 border-slate-100 px-6 py-4">
            <h2 className="font-extrabold text-slate-900">Account Details</h2>
            <p className="text-xs text-slate-500">These details appear in your workspace header.</p>
          </div>

          <div className="flex-1 p-6 space-y-5">
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <label className="label flex items-center gap-2">
                  <User size={14} /> Name
                </label>
                <input
                  className="input"
                  value={form.name}
                  onChange={(e) => set({ name: e.target.value })}
                  required
                />
              </div>
              <div>
                <label className="label flex items-center gap-2">
                  <Mail size={14} /> Email
                </label>
                <input className="input" value={user.email} disabled />
              </div>
              <div>
                <label className="label">Phone</label>
                <input
                  className="input"
                  value={form.phone}
                  onChange={(e) => set({ phone: e.target.value })}
                  placeholder="+63 9XX XXX XXXX"
                />
              </div>
            </div>
          </div>

          <div className="border-t-2 border-slate-100 px-6 py-4 flex items-center justify-between gap-4">
            {error ? (
              <span className="text-sm font-semibold text-rose-600">{error}</span>
            ) : photoBusy ? (
              <span className="text-sm font-semibold text-slate-500">Uploading photo...</span>
            ) : saved ? (
              <span className="flex items-center gap-1.5 text-sm font-semibold text-brand-700">
                <BadgeCheck size={15} /> Profile updated!
              </span>
            ) : (
              <span />
            )}
            <button type="submit" className="btn-primary px-6 py-2.5" disabled={saving || photoBusy}>
              <Save size={16} /> {saving ? "Saving..." : "Save changes"}
            </button>
          </div>
        </section>
      </div>
    </form>
  );
}
