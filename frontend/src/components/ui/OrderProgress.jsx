import { Check } from "lucide-react";
import { ORDER_FLOW, ORDER_STATUS_LABEL } from "../../lib/constants";

// Shopee-style horizontal progress tracker.
export default function OrderProgress({ status }) {
  const currentIdx = ORDER_FLOW.indexOf(status);

  return (
    <ol className="flex items-start gap-2 overflow-x-auto pb-2">
      {ORDER_FLOW.map((step, i) => {
        const reached = currentIdx >= i;
        const isCurrent = currentIdx === i;
        return (
          <li key={step} className="flex-1 min-w-[88px]">
            <div className="flex items-center">
              <div
                className={`grid h-8 w-8 shrink-0 place-items-center rounded-full border-2 transition ${
                  reached
                    ? "bg-brand-600 border-brand-600 text-white"
                    : "bg-white border-slate-300 text-slate-400"
                } ${isCurrent ? "ring-4 ring-brand-100" : ""}`}
              >
                {reached ? <Check size={16} /> : <span className="text-xs">{i + 1}</span>}
              </div>
              {i < ORDER_FLOW.length - 1 && (
                <div
                  className={`flex-1 h-1 mx-1 rounded-full ${
                    currentIdx > i ? "bg-brand-500" : "bg-slate-200"
                  }`}
                />
              )}
            </div>
            <div
              className={`mt-2 text-xs font-medium ${
                reached ? "text-brand-700" : "text-slate-400"
              }`}
            >
              {ORDER_STATUS_LABEL[step]}
            </div>
          </li>
        );
      })}
    </ol>
  );
}
