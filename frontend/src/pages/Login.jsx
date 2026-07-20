import { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import {
  LogIn,
  AlertCircle,
  CheckCircle2,
  ArrowLeft,
  Eye,
  EyeOff,
  Sprout,
} from "lucide-react";
import Logo from "../components/ui/Logo";
import { useAuth } from "../contexts/AuthContext";
import ConfirmationModal from "../components/ui/ConfirmationModal";

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const from = location.state?.from || null;

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPw, setShowPw] = useState(false);
  const [err, setErr] = useState("");
  const [loading, setLoading] = useState(false);
  const [helpOpen, setHelpOpen] = useState(false);

  const onSubmit = async (e) => {
    e.preventDefault();
    setErr("");
    setLoading(true);
    try {
      const u = await login(email, password);
      navigate(from || `/${u.role}`, { replace: true });
    } catch (ex) {
      setErr(ex.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex">
      {/* ── Left panel — brand-800 solid ── */}
      <div className="hidden xl:flex xl:w-1/2 flex-col justify-between bg-brand-800 px-14 py-12">
        <Logo light />
        <div>
          <h2 className="font-display text-4xl font-extrabold text-white leading-tight">
            Built for modern
            <br />
            farming teams.
          </h2>
          <p className="mt-4 text-brand-200 text-lg max-w-md">
            Sign in to manage plantings, reservations, and delivery timelines in
            one unified platform.
          </p>
          <ul className="mt-8 space-y-3">
            {[
              "Real-time crop and order updates",
              "Cleaner buyer-farmer transaction flow",
              "AI-backed forecasts and trend visibility",
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
      <div className="flex flex-1 flex-col bg-white">
        <div className="flex flex-1 items-center justify-center px-6 py-10">
          <div className="w-full max-w-sm">
            {/* Mobile logo */}
            <div className="xl:hidden mb-6 flex justify-center">
              <Logo />
            </div>

            {/* Back to home — inside page, not in navbar */}
            <Link
              to="/"
              className="mb-6 inline-flex items-center gap-1.5 text-sm font-semibold text-slate-400 hover:text-brand-700 transition-colors"
            >
              <ArrowLeft size={14} /> Back to home
            </Link>

            <div className="mb-8">
              <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-brand-600 mb-4">
                <Sprout size={26} className="text-white" />
              </div>
              <h1 className="font-display text-3xl font-extrabold text-slate-900">
                Welcome back
              </h1>
              <p className="mt-1 text-slate-500">
                Sign in to your AgriLink account.
              </p>
            </div>

            <form onSubmit={onSubmit} className="space-y-4">
              {err && (
                <div className="flex items-start gap-2 rounded-xl border-2 border-rose-200 bg-rose-50 p-3 text-sm text-rose-700">
                  <AlertCircle size={15} className="mt-0.5 shrink-0" />
                  <span>{err}</span>
                </div>
              )}

              <div>
                <label className="label">Email address</label>
                <input
                  type="email"
                  required
                  className="input"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                />
              </div>

              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label className="text-sm font-semibold text-slate-700">
                    Password
                  </label>
                  <button
                    type="button"
                    className="text-xs font-semibold text-brand-600 hover:underline"
                    onClick={() => setHelpOpen(true)}
                  >
                    Forgot password?
                  </button>
                </div>
                <div className="relative">
                  <input
                    type={showPw ? "text" : "password"}
                    required
                    className="input pr-10"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="••••••••"
                  />
                  <button
                    type="button"
                    tabIndex={-1}
                    onClick={() => setShowPw((v) => !v)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-700 transition-colors"
                  >
                    {showPw ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>

              <button
                type="submit"
                className="btn-primary w-full py-3 text-base"
                disabled={loading}
              >
                <LogIn size={16} /> {loading ? "Signing in..." : "Sign in"}
              </button>

              <p className="text-center text-sm text-slate-500">
                No account yet?{" "}
                <Link
                  to="/register"
                  className="font-bold text-brand-700 hover:underline"
                >
                  Create one free
                </Link>
              </p>
            </form>
          </div>
        </div>
      </div>

      <ConfirmationModal
        open={helpOpen}
        title="Password reset"
        message="Connect Firebase Auth to enable password reset."
        confirmLabel="OK"
        showCancel={false}
        onClose={() => setHelpOpen(false)}
        onConfirm={() => setHelpOpen(false)}
      />
    </div>
  );
}
