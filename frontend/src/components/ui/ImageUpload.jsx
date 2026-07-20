import { useRef, useState } from "react";
import { Upload, X, Loader2, Image as ImageIcon } from "lucide-react";
import { uploadImage, deleteImage } from "../../services/storage";
import ConfirmationModal from "./ConfirmationModal";

/**
 * Controlled image picker with drag-drop, preview, and progress state.
 *
 * Props:
 *   value     – currently stored image record `{ url, path, kind } | null`
 *   onChange  – (next | null) => void
 *   folder    – Firebase Storage / mock folder name (e.g. "farms")
 *   label     – caption shown above the dropzone
 *   aspect    – TailwindCSS aspect-ratio class, defaults to "aspect-video"
 */
export default function ImageUpload({
  value,
  onChange,
  onBusyChange,
  folder = "uploads",
  label = "Photo",
  aspect = "aspect-video",
  maxDim,
  quality,
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [drag, setDrag] = useState(false);
  const [showRemoveConfirm, setShowRemoveConfirm] = useState(false);
  const inputRef = useRef(null);

  const handleFiles = async (files) => {
    const file = files?.[0];
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      setError("Please choose an image file (JPG, PNG, WebP).");
      return;
    }
    if (file.size > 8 * 1024 * 1024) {
      setError("Image is larger than 8 MB. Please choose a smaller file.");
      return;
    }
    setError("");
    setBusy(true);
    onBusyChange?.(true);
    try {
      const next = await uploadImage(file, folder, { maxDim, quality });
      onChange?.(next);
    } catch (e) {
      setError(e?.message || "Upload failed.");
    } finally {
      setBusy(false);
      onBusyChange?.(false);
    }
  };

  const onDrop = (e) => {
    e.preventDefault();
    setDrag(false);
    handleFiles(e.dataTransfer.files);
  };

  const remove = async () => {
    if (value) await deleteImage(value);
    onChange?.(null);
    setShowRemoveConfirm(false);
  };

  return (
    <div>
      {label && <label className="label">{label}</label>}
      <div
        onDragOver={(e) => {
          e.preventDefault();
          setDrag(true);
        }}
        onDragLeave={() => setDrag(false)}
        onDrop={onDrop}
        className={`relative ${aspect} w-full overflow-hidden rounded-xl border-2 border-dashed transition ${
          drag ? "border-brand-500 bg-brand-50" : "border-slate-300 bg-slate-50"
        }`}
      >
        {value?.url ? (
          <>
            <img
              src={value.url}
              alt=""
              className="absolute inset-0 h-full w-full object-cover"
            />
            <button
              type="button"
              onClick={() => setShowRemoveConfirm(true)}
              className="absolute top-2 right-2 grid h-8 w-8 place-items-center rounded-full bg-white/90 text-slate-600 hover:bg-white hover:text-rose-600 shadow"
              title="Remove photo"
            >
              <X size={16} />
            </button>
          </>
        ) : (
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            className="absolute inset-0 flex flex-col items-center justify-center gap-1 text-slate-500 hover:text-brand-700"
            disabled={busy}
          >
            {busy ? (
              <>
                <Loader2 className="animate-spin" size={22} />
                <span className="text-sm">Uploading…</span>
              </>
            ) : (
              <>
                <div className="grid h-10 w-10 place-items-center rounded-full bg-white shadow-sm">
                  <Upload size={18} />
                </div>
                <span className="text-sm font-medium">
                  Click to upload or drag &amp; drop
                </span>
                <span className="text-xs text-slate-400">
                  JPG, PNG or WebP — up to 8 MB
                </span>
              </>
            )}
          </button>
        )}
      </div>

      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => {
          handleFiles(e.target.files);
          // Allow re-selecting the same file after a failed upload.
          e.target.value = "";
        }}
      />

      {error && <p className="mt-2 text-xs text-rose-600">{error}</p>}

      <ConfirmationModal
        open={showRemoveConfirm}
        title="Remove photo"
        message="Remove this photo?"
        confirmLabel="Remove"
        cancelLabel="Keep"
        onClose={() => setShowRemoveConfirm(false)}
        onConfirm={remove}
      />
    </div>
  );
}

// Tiny inline thumbnail used in lists / cards.
export function ImageThumb({ image, alt = "", className = "" }) {
  if (!image?.url) {
    return (
      <div
        className={`grid place-items-center bg-slate-100 text-slate-400 ${className}`}
      >
        <ImageIcon size={18} />
      </div>
    );
  }
  return (
    <img src={image.url} alt={alt} className={`object-cover ${className}`} />
  );
}
