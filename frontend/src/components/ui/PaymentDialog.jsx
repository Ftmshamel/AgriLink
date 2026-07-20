import { useMemo, useState } from "react";
import {
  X, ArrowLeft, ShieldCheck, Loader2, CheckCircle2, CreditCard, Wallet,
  Landmark, Banknote,
} from "lucide-react";
import {
  PAYMENT_MODE, PAYMENT_MODE_INFO, PAYMENT_METHODS,
} from "../../lib/constants";
import { fmtPHP } from "../../lib/format";

const METHOD_ICON = {
  GCash:     Wallet,
  Maya:      Wallet,
  BPI:       Landmark,
  BDO:       Landmark,
  UnionBank: Landmark,
  Cash:      Banknote,
};

const fakeReference = (method) =>
  `${method.slice(0, 2).toUpperCase()}-${Math.random().toString(36).slice(2, 8).toUpperCase()}-${Date.now().toString().slice(-4)}`;

/**
 * Multi-step payment dialog used both for the initial pre-order checkout
 * and for paying off a remaining balance later.
 *
 * Props:
 *   open       – boolean
 *   onClose    – () => void
 *   title      – heading of the dialog
 *   subtitle   – contextual line under the heading
 *   total      – total order amount in PHP (used for full-payment math)
 *   amountDue  – amount the buyer can pay this round (== total for new orders,
 *                == remaining balance when settling later)
 *   modes      – which PAYMENT_MODE entries to expose (defaults to all)
 *   forcedMode – when set, skip the mode-selection step (e.g. "balance only")
 *   onConfirm  – async ({ mode, method, amount, reference, downpaymentPct }) => Promise<void>
 *   submitLabel – label for the final confirm button
 */
export default function PaymentDialog({
  open,
  onClose,
  title,
  subtitle,
  total,
  amountDue,
  modes,
  forcedMode = null,
  onConfirm,
  submitLabel = "Confirm payment",
}) {
  const availableModes = useMemo(
    () => (modes || Object.values(PAYMENT_MODE)),
    [modes]
  );

  const [step, setStep]     = useState(forcedMode ? 2 : 1); // 1 mode, 2 method, 3 review, 4 done
  const [mode, setMode]     = useState(forcedMode || PAYMENT_MODE.DOWN_50);
  const [method, setMethod] = useState(PAYMENT_METHODS[0].id);
  const [busy, setBusy]     = useState(false);
  const [error, setError]   = useState("");

  if (!open) return null;

  const downPct = forcedMode === "balance"
    ? 100
    : PAYMENT_MODE_INFO[mode]?.downPct ?? 100;

  const amountNow = forcedMode === "balance"
    ? amountDue
    : Math.round((total * downPct) / 100);

  const balanceAfter = (total ?? amountDue) - amountNow;

  const next = () => { setError(""); setStep((s) => s + 1); };
  const back = () => { setError(""); setStep((s) => Math.max(forcedMode ? 2 : 1, s - 1)); };

  const confirm = async () => {
    setBusy(true);
    setError("");
    try {
      await onConfirm({
        mode,
        method,
        amount: amountNow,
        downpaymentPct: downPct,
        reference: fakeReference(method),
      });
      setStep(4);
    } catch (e) {
      setError(e?.message || "Could not process payment.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-white/65 p-4 backdrop-blur-sm animate-fade-in">
      <div className="w-full max-w-lg card border-white/70 bg-white/95 p-6 relative shadow-xl shadow-slate-200/70">
        <button onClick={onClose} className="absolute top-3 right-3 text-slate-400 hover:text-slate-700">
          <X size={20} />
        </button>

        <div className="flex items-start gap-3 pr-6">
          <div className="grid h-10 w-10 place-items-center rounded-xl bg-brand-50 text-brand-700">
            <CreditCard size={20} />
          </div>
          <div>
            <h3 className="font-display text-xl font-bold text-slate-900">{title}</h3>
            {subtitle && <p className="text-sm text-slate-500 mt-0.5">{subtitle}</p>}
          </div>
        </div>

        {step !== 4 && (
          <Stepper step={step} forcedMode={forcedMode} />
        )}

        {error && (
          <div className="mt-4 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-700">
            {error}
          </div>
        )}

        {step === 1 && (
          <div className="mt-5 space-y-3">
            {availableModes.map((m) => {
              const info = PAYMENT_MODE_INFO[m];
              if (!info) return null;
              const upfront = Math.round((total * info.downPct) / 100);
              const selected = mode === m;
              return (
                <button
                  key={m}
                  type="button"
                  onClick={() => setMode(m)}
                  className={`w-full text-left rounded-xl border-2 p-4 transition flex items-center gap-3 ${
                    selected ? "border-brand-500 bg-brand-50" : "border-slate-200 hover:border-slate-300"
                  }`}
                >
                  <div className={`mt-0.5 h-4 w-4 rounded-full border-2 ${selected ? "border-brand-600 bg-brand-600" : "border-slate-300"}`} />
                  <div className="flex-1 min-w-0">
                    <div className="font-semibold text-slate-900">{info.label}</div>
                    <div className="text-xs text-slate-500 mt-0.5">{info.helper}</div>
                  </div>
                  <div className="text-right">
                    <div className="text-xs text-slate-500">Pay now</div>
                    <div className="font-display font-bold text-slate-900">{fmtPHP(upfront)}</div>
                  </div>
                </button>
              );
            })}

            <div className="flex justify-end pt-2">
              <button type="button" className="btn-primary" onClick={next}>Continue</button>
            </div>
          </div>
        )}

        {step === 2 && (
          <div className="mt-5 space-y-3">
            <div className="grid grid-cols-2 gap-2">
              {PAYMENT_METHODS.map((m) => {
                const Icon = METHOD_ICON[m.id] || CreditCard;
                const selected = method === m.id;
                return (
                  <button
                    key={m.id}
                    type="button"
                    onClick={() => setMethod(m.id)}
                    className={`text-left rounded-xl border-2 p-3 transition flex items-center gap-3 ${
                      selected ? "border-brand-500 bg-brand-50" : "border-slate-200 hover:border-slate-300"
                    }`}
                  >
                    <div className={`grid h-9 w-9 place-items-center rounded-lg ${selected ? "bg-brand-600 text-white" : "bg-slate-100 text-slate-600"}`}>
                      <Icon size={16} />
                    </div>
                    <div className="min-w-0">
                      <div className="font-semibold text-slate-900 truncate">{m.label}</div>
                      <div className="text-xs text-slate-500">{m.tag}</div>
                    </div>
                  </button>
                );
              })}
            </div>

            <div className="flex items-center justify-between pt-2">
              {!forcedMode ? (
                <button type="button" className="btn-ghost" onClick={back}>
                  <ArrowLeft size={16} /> Back
                </button>
              ) : <span />}
              <button type="button" className="btn-primary" onClick={next}>Continue</button>
            </div>
          </div>
        )}

        {step === 3 && (
          <div className="mt-5 space-y-4">
            <div className="rounded-xl border border-slate-200 bg-slate-50 p-4 space-y-2 text-sm">
              <Row k="Amount due now" v={fmtPHP(amountNow)} bold />
              {balanceAfter > 0 && total != null && (
                <Row k="Remaining balance" v={fmtPHP(balanceAfter)} muted />
              )}
              <Row k="Method" v={method} />
              {!forcedMode && (
                <Row k="Mode" v={PAYMENT_MODE_INFO[mode]?.label} />
              )}
            </div>

            <div className="rounded-lg bg-brand-50 border border-brand-100 p-3 flex items-start gap-2 text-sm text-brand-800">
              <ShieldCheck size={16} className="mt-0.5 shrink-0" />
              <span>
                This is a demo payment flow — no real money is charged. In production this would
                hand off to your selected provider's secure checkout.
              </span>
            </div>

            <div className="flex items-center justify-between pt-2">
              <button type="button" className="btn-ghost" onClick={back} disabled={busy}>
                <ArrowLeft size={16} /> Back
              </button>
              <button type="button" className="btn-primary" onClick={confirm} disabled={busy}>
                {busy ? <Loader2 className="animate-spin" size={16} /> : <ShieldCheck size={16} />}
                {busy ? "Processing…" : submitLabel}
              </button>
            </div>
          </div>
        )}

        {step === 4 && (
          <div className="mt-6 text-center">
            <div className="mx-auto h-14 w-14 rounded-full bg-brand-100 grid place-items-center text-brand-700">
              <CheckCircle2 size={28} />
            </div>
            <h4 className="mt-3 font-display text-lg font-bold text-slate-900">Payment confirmed</h4>
            <p className="text-sm text-slate-500 mt-1">
              We've recorded your {fmtPHP(amountNow)} payment via {method}.
              {balanceAfter > 0 && total != null && (
                <> A balance of {fmtPHP(balanceAfter)} remains.</>
              )}
            </p>
            <button className="btn-primary mt-5" onClick={onClose}>Done</button>
          </div>
        )}
      </div>
    </div>
  );
}

function Stepper({ step, forcedMode }) {
  const labels = forcedMode
    ? ["Method", "Review", "Done"]
    : ["Mode", "Method", "Review", "Done"];
  return (
    <ol className="mt-5 flex items-center gap-2">
      {labels.map((l, i) => {
        const idx = i + (forcedMode ? 2 : 1);
        const reached = step >= idx;
        return (
          <li key={l} className="flex-1 flex items-center gap-2">
            <span className={`h-1.5 flex-1 rounded-full ${reached ? "bg-brand-500" : "bg-slate-200"}`} />
            <span className={`text-xs font-medium ${reached ? "text-brand-700" : "text-slate-400"}`}>{l}</span>
          </li>
        );
      })}
    </ol>
  );
}

function Row({ k, v, bold, muted }) {
  return (
    <div className="flex items-center justify-between">
      <span className={`text-slate-500 ${muted ? "text-xs" : ""}`}>{k}</span>
      <span className={`${bold ? "font-display font-bold text-slate-900" : "text-slate-800"}`}>{v}</span>
    </div>
  );
}
