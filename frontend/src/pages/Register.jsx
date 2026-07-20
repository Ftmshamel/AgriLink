import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import {
  UserPlus,
  AlertCircle,
  MapPin,
  Sprout,
  ShoppingBasket,
  ArrowLeft,
  Eye,
  EyeOff,
  CheckCircle2,
} from "lucide-react";
import Logo from "../components/ui/Logo";
import MapPicker from "../components/map/MapPicker";
import { useAuth } from "../contexts/AuthContext";
import { ROLES } from "../lib/constants";

export default function Register() {
  const { register } = useAuth();
  const navigate = useNavigate();

  const [step, setStep] = useState(1);
  const [role, setRole] = useState(ROLES.FARMER);
  const [form, setForm] = useState({
    name: "",
    email: "",
    password: "",
    phone: "",
    farmName: "",
    barangay: "",
    municipality: "",
    province: "",
    location: null,
    businessType: "Restaurant",
    address: "",
  });
  const [showPw, setShowPw] = useState(false);
  const [err, setErr] = useState("");
  const [loading, setLoading] = useState(false);

  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const next = (e) => {
    e.preventDefault();
    setErr("");
    if (!form.name || !form.email || !form.password) {
      setErr("Please fill in your name, email and password.");
      return;
    }
    if (form.password.length < 6) {
      setErr("Password must be at least 6 characters.");
      return;
    }
    setStep(2);
  };

  const submit = async (e) => {
    e.preventDefault();
    setErr("");
    if (role === ROLES.FARMER && !form.location) {
      setErr("Please pin your farm location on the map.");
      return;
    }
    setLoading(true);
    try {
      const payload = { ...form, role, verified: role === ROLES.BUYER };
      const u = await register(payload);
      navigate(`/${u.role}`, { replace: true });
    } catch (ex) {
      setErr(ex.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex">
      {/* ── Left panel — brand-800 (same as Login) ── */}
      <div className="hidden xl:flex xl:w-1/2 flex-col justify-between bg-brand-800 px-14 py-12">
        <Logo light />
        <div>
          <h2 className="font-display text-4xl font-extrabold text-white leading-tight">
            Join the AgriLink
            <br />
            community today.
          </h2>
          <p className="mt-4 text-brand-200 text-lg max-w-md">
            Connect directly with verified farmers or start selling your harvest
            to buyers across the Philippines.
          </p>
          <ul className="mt-8 space-y-3">
            {[
              "Free to join — no subscription needed",
              "AI-powered harvest date prediction",
              "GCash & Maya payment support",
              "Real-time order tracking",
            ].map((item) => (
              <li key={item} className="flex items-center gap-3 text-brand-200">
                <CheckCircle2 size={16} className="text-brand-400 shrink-0" />
                {item}
              </li>
            ))}
          </ul>
        </div>
        <p className="text-xs text-brand-500">
          © {new Date().getFullYear()} AgriLink
        </p>
      </div>

      {/* ── Right panel — form ── */}
      <div className="flex flex-1 flex-col bg-white overflow-y-auto">
        {/* Progress bar at very top of right panel */}
        <div className="w-full h-1.5 bg-slate-100 shrink-0">
          <div
            className="h-full bg-brand-600 transition-all duration-300"
            style={{ width: step === 1 ? "50%" : "100%" }}
          />
        </div>

        <div className="flex flex-1 items-start justify-center px-6 py-10">
          <div className="w-full max-w-md">
            {/* Mobile logo */}
            <div className="xl:hidden mb-6 flex justify-center">
              <Logo />
            </div>

            {/* Back to home */}
            <Link
              to="/"
              className="mb-6 inline-flex items-center gap-1.5 text-sm font-semibold text-slate-400 hover:text-brand-700 transition-colors"
            >
              <ArrowLeft size={14} /> Back to home
            </Link>

            {/* Heading */}
            <div className="mb-7">
              <h1 className="font-display text-3xl font-extrabold text-slate-900">
                {step === 1
                  ? "Create your account"
                  : role === ROLES.FARMER
                    ? "Set up your farm"
                    : "Business details"}
              </h1>
              <p className="mt-1 text-slate-500 text-sm">
                Step <span className="font-bold text-brand-600">{step}</span> of
                2
              </p>
            </div>

            {err && (
              <div className="mb-5 flex items-start gap-2 rounded-xl border-2 border-rose-200 bg-rose-50 p-3 text-sm text-rose-700">
                <AlertCircle size={15} className="mt-0.5 shrink-0" />
                <span>{err}</span>
              </div>
            )}

            {step === 1 && (
              <form onSubmit={next} className="space-y-5">
                {/* Role picker */}
                <div>
                  <label className="label mb-2 block">I am a…</label>
                  <div className="grid grid-cols-2 gap-3">
                    <RoleCard
                      icon={Sprout}
                      label="Farmer"
                      description="Producer / supplier"
                      selected={role === ROLES.FARMER}
                      onClick={() => setRole(ROLES.FARMER)}
                    />
                    <RoleCard
                      icon={ShoppingBasket}
                      label="Buyer"
                      description="Restaurant / wholesaler"
                      selected={role === ROLES.BUYER}
                      onClick={() => setRole(ROLES.BUYER)}
                    />
                  </div>
                  <p className="mt-2 text-xs text-slate-400">
                    Admin accounts are created internally by the AgriLink team.
                  </p>
                </div>

                <div className="grid gap-3 sm:grid-cols-2">
                  <div>
                    <label className="label">
                      Full name{role === ROLES.BUYER ? " / Business name" : ""}
                    </label>
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
                      placeholder="+63 9XX XXX XXXX"
                    />
                  </div>
                </div>

                <div className="grid gap-3 sm:grid-cols-2">
                  <div>
                    <label className="label">Email</label>
                    <input
                      type="email"
                      className="input"
                      value={form.email}
                      onChange={(e) => set({ email: e.target.value })}
                      required
                    />
                  </div>
                  <div>
                    <label className="label">Password</label>
                    <div className="relative">
                      <input
                        type={showPw ? "text" : "password"}
                        className="input pr-10"
                        value={form.password}
                        onChange={(e) => set({ password: e.target.value })}
                        required
                        placeholder="Min. 6 characters"
                      />
                      <button
                        type="button"
                        tabIndex={-1}
                        onClick={() => setShowPw((v) => !v)}
                        className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-700 transition-colors"
                      >
                        {showPw ? <EyeOff size={15} /> : <Eye size={15} />}
                      </button>
                    </div>
                  </div>
                </div>

                <button
                  type="submit"
                  className="btn-primary w-full py-3 text-base"
                >
                  Continue →
                </button>

                <p className="text-center text-sm text-slate-500">
                  Already have an account?{" "}
                  <Link
                    to="/login"
                    className="font-bold text-brand-700 hover:underline"
                  >
                    Sign in
                  </Link>
                </p>
              </form>
            )}

            {step === 2 && (
              <form onSubmit={submit} className="space-y-4">
                {role === ROLES.FARMER ? (
                  <>
                    <div className="grid gap-3 sm:grid-cols-2">
                      <div>
                        <label className="label">Farm name</label>
                        <input
                          className="input"
                          value={form.farmName}
                          onChange={(e) => set({ farmName: e.target.value })}
                          placeholder="e.g. Hilltop Organic Farm"
                        />
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
                          onChange={(e) =>
                            set({ municipality: e.target.value })
                          }
                        />
                      </div>
                      <div>
                        <label className="label">Province</label>
                        <input
                          className="input"
                          value={form.province}
                          onChange={(e) => set({ province: e.target.value })}
                        />
                      </div>
                    </div>

                    <div>
                      <label className="label flex items-center gap-1.5">
                        <MapPin size={13} /> Pin your farm location on the map
                      </label>
                      <p className="mb-2 text-xs text-slate-400">
                        Tap anywhere on the map to drop a pin — this becomes
                        your pickup / delivery hub.
                      </p>
                      <MapPicker
                        value={form.location}
                        onChange={(loc) =>
                          set({
                            location: loc,
                            barangay: loc?.barangay || form.barangay,
                            municipality:
                              loc?.municipality || form.municipality,
                            province: loc?.province || form.province,
                          })
                        }
                        height={280}
                      />
                      {form.location && (
                        <p className="mt-1.5 text-xs text-brand-600 font-semibold">
                          Pinned: {form.location.lat.toFixed(5)},{" "}
                          {form.location.lng.toFixed(5)} —{" "}
                          {form.location.displayName || ""}
                        </p>
                      )}
                    </div>
                  </>
                ) : (
                  <div className="grid gap-3 sm:grid-cols-2">
                    <div>
                      <label className="label">Business type</label>
                      <select
                        className="input"
                        value={form.businessType}
                        onChange={(e) => set({ businessType: e.target.value })}
                      >
                        <option>Restaurant</option>
                        <option>Wholesaler</option>
                        <option>Hotel</option>
                        <option>Supermarket</option>
                        <option>Other</option>
                      </select>
                    </div>
                    <div>
                      <label className="label">Business address</label>
                      <input
                        className="input"
                        value={form.address}
                        onChange={(e) => set({ address: e.target.value })}
                        placeholder="City, Province"
                      />
                    </div>
                  </div>
                )}

                <div className="flex items-center justify-between gap-3 pt-2 border-t-2 border-slate-100">
                  <button
                    type="button"
                    onClick={() => setStep(1)}
                    className="btn-ghost"
                  >
                    <ArrowLeft size={15} /> Back
                  </button>
                  <button
                    type="submit"
                    className="btn-primary px-7 py-2.5"
                    disabled={loading}
                  >
                    <UserPlus size={15} />{" "}
                    {loading ? "Creating..." : "Create account"}
                  </button>
                </div>
              </form>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function RoleCard({ icon: Icon, label, description, selected, onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`text-left rounded-2xl border-2 p-4 transition-all ${
        selected
          ? "border-brand-600 bg-brand-50 shadow-soft"
          : "border-slate-200 bg-white hover:border-brand-300"
      }`}
    >
      <div
        className={`grid h-10 w-10 place-items-center rounded-xl ${
          selected ? "bg-brand-600 text-white" : "bg-slate-100 text-slate-600"
        }`}
      >
        <Icon size={18} />
      </div>
      <div className="mt-3 font-extrabold text-slate-900">{label}</div>
      <div className="text-xs text-slate-500">{description}</div>
    </button>
  );
}
