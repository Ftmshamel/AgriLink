import { createContext, useCallback, useContext, useState } from "react";
import { CheckCircle2, XCircle, Info, AlertTriangle, X } from "lucide-react";

const ToastCtx = createContext(null);

let _toastId = 0;

const ICONS = {
  success: <CheckCircle2 size={18} className="text-brand-600 shrink-0" />,
  error:   <XCircle     size={18} className="text-rose-600 shrink-0" />,
  info:    <Info        size={18} className="text-blue-600 shrink-0" />,
  warning: <AlertTriangle size={18} className="text-harvest-600 shrink-0" />,
};

const BG = {
  success: "border-brand-200 bg-white",
  error:   "border-rose-200 bg-white",
  info:    "border-blue-200 bg-white",
  warning: "border-harvest-200 bg-white",
};

export function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([]);

  const dismiss = useCallback((id) => {
    setToasts((t) => t.filter((x) => x.id !== id));
  }, []);

  const toast = useCallback((message, type = "info", duration = 4000) => {
    const id = ++_toastId;
    setToasts((t) => [...t, { id, message, type }]);
    if (duration > 0) setTimeout(() => dismiss(id), duration);
    return id;
  }, [dismiss]);

  return (
    <ToastCtx.Provider value={{ toast, dismiss }}>
      {children}
      {/* Toast container */}
      <div className="fixed top-4 right-4 z-[9999] flex flex-col gap-2 w-80 max-w-[calc(100vw-2rem)]">
        {toasts.map((t) => (
          <div
            key={t.id}
            className={`flex items-start gap-3 rounded-2xl border-2 px-4 py-3 shadow-strong animate-slide-up ${BG[t.type] || BG.info}`}
          >
            {ICONS[t.type] || ICONS.info}
            <p className="flex-1 text-sm font-medium text-slate-800">{t.message}</p>
            <button
              onClick={() => dismiss(t.id)}
              className="text-slate-400 hover:text-slate-600 transition-colors shrink-0"
            >
              <X size={14} />
            </button>
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export const useToast = () => {
  const ctx = useContext(ToastCtx);
  if (!ctx) throw new Error("useToast must be inside <ToastProvider>");
  return ctx;
};
