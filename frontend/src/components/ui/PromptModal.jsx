import React from "react";

export default function PromptModal({
  open,
  title,
  message,
  error,
  label = "Value",
  value,
  onChange,
  inputType = "text",
  placeholder = "",
  confirmLabel = "Save",
  cancelLabel = "Cancel",
  onConfirm,
  onClose,
}) {
  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative w-full max-w-md rounded-lg bg-white p-6 shadow-xl">
        <h3 className="text-lg font-bold text-slate-900">{title}</h3>
        <p className="mt-2 text-sm text-slate-600">{message}</p>
        <div className="mt-4 space-y-2">
          <label className="text-sm font-semibold text-slate-700">
            {label}
          </label>
          <input
            type={inputType}
            className="input"
            value={value}
            onChange={(e) => onChange?.(e.target.value)}
            placeholder={placeholder}
            autoFocus
          />
          {error && <p className="text-xs text-rose-600">{error}</p>}
        </div>
        <div className="mt-4 flex justify-end gap-3">
          <button
            className="rounded-lg px-4 py-2 text-sm bg-slate-100 hover:bg-slate-200"
            onClick={onClose}
          >
            {cancelLabel}
          </button>
          <button
            className="rounded-lg px-4 py-2 text-sm bg-brand-700 text-white hover:bg-brand-800"
            onClick={() => onConfirm?.()}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
