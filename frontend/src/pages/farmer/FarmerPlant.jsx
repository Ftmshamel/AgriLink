import { useMemo, useState } from "react";
import {
  Sprout,
  Brain,
  Loader2,
  CheckCircle2,
  Leaf,
  Pencil,
  Trash2,
} from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import { api } from "../../services/api";
import { fmtDate } from "../../lib/format";
import { getPlantingAvailability } from "../../lib/stock";
import ImageUpload from "../../components/ui/ImageUpload";
import { ImageThumb } from "../../components/ui/ImageUpload";
import ConfirmationModal from "../../components/ui/ConfirmationModal";
import PromptModal from "../../components/ui/PromptModal";

export default function FarmerPlant() {
  const { user } = useAuth();
  const plantings = useDb(
    () => db.listPlantings({ farmerId: user.id }),
    [user.id],
  );
  const orders = useDb(() => db.listOrders({ farmerId: user.id }), [user.id]);

  const [crop, setCrop] = useState("");
  const [variety, setVariety] = useState("");
  const [datePlanted, setDatePlanted] = useState(
    new Date().toISOString().slice(0, 10),
  );
  const [areaHectares, setAreaHectares] = useState(0.5);
  const [expectedYieldKg, setExpectedYieldKg] = useState(500);
  const [preOrderStockKg, setPreOrderStockKg] = useState(500);
  const [allowBulkPreorder, setAllowBulkPreorder] = useState(true);
  const [maxPerAccountKg, setMaxPerAccountKg] = useState(50);
  const [pricePerKg, setPricePerKg] = useState(50);
  const [notes, setNotes] = useState("");
  const [cropPhoto, setCropPhoto] = useState(null);
  const [forecast, setForecast] = useState(null);
  const [loading, setLoading] = useState(false);
  const [saved, setSaved] = useState(false);
  const [savingNew, setSavingNew] = useState(false);
  const [formMessage, setFormMessage] = useState("");
  const [formError, setFormError] = useState("");
  const [showForecastModal, setShowForecastModal] = useState(false);
  const [editing, setEditing] = useState(null);
  const [savingEdit, setSavingEdit] = useState(false);
  const [deletingId, setDeletingId] = useState("");
  const [confirmDelete, setConfirmDelete] = useState(null);
  const [renewPrompt, setRenewPrompt] = useState(null);

  const runForecast = async () => {
    const cropName = crop.trim();
    if (!cropName) {
      setFormError("Crop name is required.");
      return;
    }
    setSaved(false);
    setFormMessage("");
    setFormError("");
    setLoading(true);
    try {
      const data = await api.forecastHarvest({
        crop: cropName,
        datePlanted,
        region: user.region,
      });
      setForecast(data);
      setShowForecastModal(true);
    } finally {
      setLoading(false);
    }
  };

  const savePlanting = async () => {
    if (!forecast) return;
    const cropName = crop.trim();
    if (!cropName) {
      setFormError("Crop name is required.");
      return;
    }
    setSavingNew(true);
    setFormError("");
    setFormMessage("");
    try {
      await db.createPlanting({
        farmerId: user.id,
        crop: cropName,
        variety,
        datePlanted: new Date(datePlanted).toISOString(),
        estimatedHarvest: new Date(
          forecast.estimated_harvest_date,
        ).toISOString(),
        growthDays: forecast.growth_days,
        areaHectares: Number(areaHectares),
        expectedYieldKg: Number(expectedYieldKg),
        preOrderStockKg: Number(preOrderStockKg || 0),
        allowBulkPreorder,
        maxPerAccountKg: allowBulkPreorder
          ? null
          : Number(maxPerAccountKg || 0),
        pricePerKg: Number(pricePerKg),
        notes,
        photo: cropPhoto,
        status: "growing",
      });
      setSaved(true);
      setFormMessage("Listing saved successfully.");
      setShowForecastModal(false);
    } catch (e) {
      setFormError(e?.message || "Failed to save listing.");
    } finally {
      setSavingNew(false);
    }
  };

  const sortedPlantings = useMemo(
    () =>
      [...plantings].sort(
        (a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0),
      ),
    [plantings],
  );

  const startEdit = (p) => {
    setFormMessage("");
    setFormError("");
    setEditing({
      id: p.id,
      crop: p.crop || "",
      variety: p.variety || "",
      expectedYieldKg: p.expectedYieldKg || 0,
      preOrderStockKg: p.preOrderStockKg ?? p.expectedYieldKg ?? 0,
      allowBulkPreorder: p.allowBulkPreorder !== false,
      maxPerAccountKg: p.maxPerAccountKg ?? 0,
      pricePerKg: p.pricePerKg || 0,
      notes: p.notes || "",
      estimatedHarvest: (p.estimatedHarvest || "").slice(0, 10),
      photo: p.photo || null,
    });
  };

  const saveEdit = async () => {
    if (!editing?.id) return;
    const cropName = (editing.crop || "").trim();
    if (!cropName) {
      setFormError("Crop name is required.");
      return;
    }
    setFormError("");
    setFormMessage("");
    setSavingEdit(true);
    try {
      await db.updatePlanting(editing.id, {
        crop: cropName,
        variety: editing.variety,
        expectedYieldKg: Number(editing.expectedYieldKg || 0),
        preOrderStockKg: Number(editing.preOrderStockKg || 0),
        allowBulkPreorder: !!editing.allowBulkPreorder,
        maxPerAccountKg: editing.allowBulkPreorder
          ? null
          : Number(editing.maxPerAccountKg || 0),
        pricePerKg: Number(editing.pricePerKg || 0),
        notes: editing.notes,
        estimatedHarvest: editing.estimatedHarvest
          ? new Date(editing.estimatedHarvest).toISOString()
          : null,
        photo: editing.photo || null,
      });
      setEditing(null);
      setFormMessage("Listing updated.");
    } catch (e) {
      setFormError(e?.message || "Failed to update listing.");
    } finally {
      setSavingEdit(false);
    }
  };

  const deleteListing = async (p) => {
    setConfirmDelete(p);
  };

  const renewListing = async (p) => {
    const current = getPlantingAvailability(p, orders);
    setRenewPrompt({
      planting: p,
      defaultValue: String(Math.max(10, Number(p.expectedYieldKg || 0))),
      currentStock: current.stockKg,
      value: String(Math.max(10, Number(p.expectedYieldKg || 0))),
      error: "",
    });
  };

  return (
    <div className="flex-1 flex flex-col space-y-6 min-h-0">
      {/* Page header */}
      <div className="border-l-4 border-brand-600 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">
          List Crops
        </h1>
        <p className="text-sm text-slate-500">
          Add crops for buyers to pre-order. AgriLink automatically predicts the
          harvest date when you save a listing.
        </p>
      </div>

      <div className="grid gap-6 items-start lg:grid-cols-[0.95fr_1.05fr] xl:grid-cols-[0.9fr_1.1fr]">
        {/* Input form */}
        <section className="card-accent p-4 space-y-3">
          <div className="flex items-center gap-2.5 pb-2 border-b border-slate-100">
            <div className="grid h-9 w-9 place-items-center rounded-lg bg-brand-600 text-white">
              <Leaf size={16} />
            </div>

            <ConfirmationModal
              open={!!confirmDelete}
              title={
                confirmDelete
                  ? `Delete listing for ${confirmDelete.crop}?`
                  : "Delete listing"
              }
              message="This cannot be undone."
              confirmLabel={deletingId ? "Deleting…" : "Delete"}
              cancelLabel="Cancel"
              onClose={() => setConfirmDelete(null)}
              onConfirm={async () => {
                if (!confirmDelete) return;
                setFormError("");
                setFormMessage("");
                setDeletingId(confirmDelete.id);
                try {
                  await db.deletePlanting(confirmDelete.id);
                  setFormMessage("Listing deleted.");
                  setConfirmDelete(null);
                } catch (e) {
                  setFormError(e?.message || "Failed to delete listing.");
                } finally {
                  setDeletingId("");
                }
              }}
            />

            <div>
              <h2 className="font-bold text-slate-900 leading-tight">
                Crop listing details
              </h2>
              <p className="text-xs text-slate-500">
                Fill in the crop details below.
              </p>
            </div>
          </div>

          <div className="grid sm:grid-cols-2 gap-3">
            <div>
              <label className="label">Crop</label>
              <input
                className="input"
                value={crop}
                onChange={(e) => {
                  setSaved(false);
                  setCrop(e.target.value);
                }}
                placeholder="e.g. Kale"
              />
            </div>
            <div>
              <label className="label">Variety (optional)</label>
              <input
                className="input"
                value={variety}
                onChange={(e) => {
                  setSaved(false);
                  setVariety(e.target.value);
                }}
                placeholder="e.g. Diamante Max"
              />
            </div>
            <div>
              <label className="label">Date planted</label>
              <input
                type="date"
                className="input"
                value={datePlanted}
                onChange={(e) => {
                  setSaved(false);
                  setDatePlanted(e.target.value);
                }}
              />
            </div>
            <div>
              <label className="label">Area (hectares)</label>
              <input
                type="number"
                min={0}
                step="0.1"
                className="input"
                value={areaHectares}
                onChange={(e) => {
                  setSaved(false);
                  setAreaHectares(e.target.value);
                }}
              />
            </div>
            <div>
              <label className="label">Expected yield (kg)</label>
              <input
                type="number"
                min={0}
                className="input"
                value={expectedYieldKg}
                onChange={(e) => {
                  setSaved(false);
                  setExpectedYieldKg(e.target.value);
                }}
              />
            </div>
            <div>
              <label className="label">Pre-order stock (kg)</label>
              <input
                type="number"
                min={0}
                className="input"
                value={preOrderStockKg}
                onChange={(e) => {
                  setSaved(false);
                  setPreOrderStockKg(e.target.value);
                }}
              />
            </div>
            <div className="sm:col-span-2 rounded-xl border border-slate-200 bg-slate-50 p-3">
              <label className="inline-flex items-center gap-2 text-sm font-semibold text-slate-700">
                <input
                  type="checkbox"
                  className="h-4 w-4 rounded border-slate-300"
                  checked={allowBulkPreorder}
                  onChange={(e) => {
                    setSaved(false);
                    setAllowBulkPreorder(e.target.checked);
                  }}
                />
                Allow bulk pre-order (first come, first served)
              </label>
              {!allowBulkPreorder && (
                <div className="mt-2">
                  <label className="label">
                    Max pre-order per account (kg)
                  </label>
                  <input
                    type="number"
                    min={1}
                    className="input"
                    value={maxPerAccountKg}
                    onChange={(e) => {
                      setSaved(false);
                      setMaxPerAccountKg(e.target.value);
                    }}
                  />
                </div>
              )}
            </div>
            <div>
              <label className="label">Price per kg (PHP)</label>
              <input
                type="number"
                min={0}
                className="input"
                value={pricePerKg}
                onChange={(e) => {
                  setSaved(false);
                  setPricePerKg(e.target.value);
                }}
              />
            </div>
          </div>

          <div>
            <label className="label">Notes</label>
            <textarea
              className="input"
              rows={2}
              value={notes}
              onChange={(e) => {
                setSaved(false);
                setNotes(e.target.value);
              }}
              placeholder="Soil type, irrigation, organic, etc."
            />
          </div>

          <ImageUpload
            label="Crop photo (shown to buyers)"
            folder="crops"
            aspect="aspect-[16/7]"
            value={cropPhoto}
            onChange={(val) => {
              setSaved(false);
              setCropPhoto(val);
            }}
          />

          <button
            type="button"
            className="btn-primary w-full py-2.5 text-sm"
            onClick={runForecast}
            disabled={loading}
          >
            {loading ? (
              <Loader2 className="animate-spin" size={16} />
            ) : (
              <Brain size={16} />
            )}
            {loading ? "Predicting harvest..." : "List crop"}
          </button>
        </section>

        <section className="card-accent flex flex-col min-h-[420px]">
          <div className="flex items-center justify-between border-b-2 border-slate-100 px-6 py-4">
            <div>
              <h2 className="font-display text-lg font-extrabold text-slate-900">
                My Listings
              </h2>
              <p className="text-xs text-slate-500">
                View and edit your crop listings shown to buyers.
              </p>
            </div>
            <span className="badge-green">
              {sortedPlantings.length} listing
              {sortedPlantings.length !== 1 ? "s" : ""}
            </span>
          </div>
          {(formError || formMessage) && (
            <div className="px-6 pt-4 text-sm">
              {formError ? (
                <p className="text-rose-600">{formError}</p>
              ) : (
                <p className="text-brand-700">{formMessage}</p>
              )}
            </div>
          )}

          <div className="flex-1 p-4">
            {sortedPlantings.length === 0 ? (
              <div className="py-12 text-center text-sm text-slate-500">
                No listings yet. Add your first crop listing.
              </div>
            ) : (
              <div className="space-y-4">
                {sortedPlantings.map((p) => {
                  const availability = getPlantingAvailability(p, orders);
                  return (
                    <article
                      key={p.id}
                      className="overflow-hidden rounded-xl border-2 border-slate-200 bg-white shadow-soft"
                    >
                      <div className="flex flex-col sm:flex-row">
                        <div className="sm:w-36 sm:shrink-0 h-20 sm:h-auto bg-slate-100 relative">
                          <ImageThumb
                            image={p.photo}
                            alt={p.crop}
                            className="absolute inset-0 h-full w-full"
                          />
                        </div>

                        <div className="flex-1 p-4">
                          <div className="flex flex-wrap items-start justify-between gap-3">
                            <div className="min-w-0">
                              <div className="flex flex-wrap items-center gap-2">
                                <h3 className="font-display text-xl font-extrabold text-slate-900">
                                  {p.crop}
                                </h3>
                                {availability.soldOut && (
                                  <span className="badge-rose">Sold out</span>
                                )}
                              </div>
                              <p className="text-xs text-slate-500">
                                {p.variety || "Standard variety"} ·{" "}
                                {p.expectedYieldKg} kg expected
                              </p>
                            </div>
                            <div className="rounded-lg bg-brand-800 px-3 py-1.5 text-right">
                              <div className="font-display text-xl font-extrabold text-white">
                                PHP {p.pricePerKg}
                                <span className="text-[11px] font-normal text-brand-200">
                                  /kg
                                </span>
                              </div>
                              <div className="text-[11px] text-brand-300">
                                Listed crop offer
                              </div>
                            </div>
                          </div>

                          <div className="mt-2.5 grid sm:grid-cols-2 gap-2">
                            <div className="rounded-md border border-slate-200 bg-slate-50 px-2.5 py-1.5 text-xs text-slate-700">
                              Harvest:{" "}
                              <strong>{fmtDate(p.estimatedHarvest)}</strong>
                            </div>
                            <div className="rounded-md border border-slate-200 bg-slate-50 px-2.5 py-1.5 text-xs text-slate-700">
                              Yield: <strong>{p.expectedYieldKg} kg</strong>
                            </div>
                            <div className="rounded-md border border-slate-200 bg-slate-50 px-2.5 py-1.5 text-xs text-slate-700 sm:col-span-2">
                              Pre-order:{" "}
                              <strong>
                                {availability.availableKg} kg available
                              </strong>{" "}
                              ({availability.reservedKg} of{" "}
                              {availability.stockKg} kg reserved)
                              {p.allowBulkPreorder === false
                                ? ` · max ${p.maxPerAccountKg || 0} kg/account`
                                : " · bulk allowed"}
                            </div>
                          </div>

                          <div className="mt-2.5 flex items-center justify-end gap-2 border-t border-slate-100 pt-2">
                            {availability.soldOut && (
                              <button
                                className="btn-primary px-3 py-1.5 text-xs"
                                onClick={() => renewListing(p)}
                              >
                                <Sprout size={14} /> Renew stock
                              </button>
                            )}
                            <button
                              className="btn-ghost px-3 py-1.5 text-xs"
                              onClick={() => startEdit(p)}
                            >
                              <Pencil size={14} /> Edit
                            </button>
                            <button
                              className="inline-flex items-center gap-1.5 rounded-lg border-2 border-rose-200 bg-rose-50 px-3 py-1.5 text-xs font-bold text-rose-700 hover:bg-rose-100"
                              onClick={() => deleteListing(p)}
                              disabled={deletingId === p.id}
                            >
                              {deletingId === p.id ? (
                                <Loader2 size={14} className="animate-spin" />
                              ) : (
                                <Trash2 size={14} />
                              )}
                              Delete
                            </button>
                          </div>
                        </div>
                      </div>
                    </article>
                  );
                })}
              </div>
            )}
          </div>
        </section>
      </div>

      {showForecastModal && forecast && (
        <div className="fixed inset-0 z-50 grid place-items-center overflow-y-auto bg-slate-900/60 p-3 sm:p-4 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-lg rounded-2xl border-2 border-slate-100 bg-white shadow-strong max-h-[92vh] overflow-hidden">
            <div className="p-5 sm:p-6 overflow-y-auto max-h-[92vh]">
              <div className="flex items-center gap-3 border-b-2 border-slate-100 pb-4">
                <div className="grid h-10 w-10 place-items-center rounded-xl bg-brand-600 text-white">
                  <Brain size={18} />
                </div>
                <div>
                  <h3 className="font-bold text-slate-900">
                    Harvest Prediction
                  </h3>
                  <p className="text-xs text-slate-500">
                    Review the automatic harvest date, then save the listing.
                  </p>
                </div>
              </div>

              <div className="mt-4 space-y-4">
                <div className="rounded-2xl bg-brand-800 p-6 text-white">
                  <p className="text-xs font-bold uppercase tracking-widest text-brand-300 mb-1">
                    Estimated harvest date
                  </p>
                  <p className="font-display text-3xl font-extrabold">
                    {fmtDate(forecast.estimated_harvest_date, "MMMM d, yyyy")}
                  </p>
                  <div className="mt-2 flex flex-wrap gap-3 text-sm text-brand-200">
                    <span>{forecast.growth_days} days from planting</span>
                    <span>·</span>
                    <span>
                      {(forecast.confidence * 100).toFixed(0)}% confidence
                    </span>
                  </div>
                </div>

                <div>
                  <div className="flex justify-between text-xs text-slate-500 mb-1">
                    <span>Model confidence</span>
                    <span className="font-bold text-brand-700">
                      {(forecast.confidence * 100).toFixed(0)}%
                    </span>
                  </div>
                  <div className="h-2.5 w-full rounded-full bg-slate-100">
                    <div
                      className="h-full rounded-full bg-brand-600 transition-all"
                      style={{
                        width: `${(forecast.confidence * 100).toFixed(0)}%`,
                      }}
                    />
                  </div>
                </div>

                {formError && (
                  <p className="text-sm text-rose-600">{formError}</p>
                )}
                {formMessage && (
                  <p className="text-sm text-brand-700">{formMessage}</p>
                )}

                <div className="flex items-center justify-end gap-2 pt-2">
                  <button
                    className="btn-ghost"
                    onClick={() => setShowForecastModal(false)}
                  >
                    Close
                  </button>
                  <button
                    className={`px-5 py-2.5 rounded-xl text-sm font-bold transition-colors flex items-center justify-center gap-2 ${
                      saved
                        ? "bg-brand-50 text-brand-700 border-2 border-brand-200"
                        : "btn-primary"
                    }`}
                    onClick={savePlanting}
                    disabled={saved || savingNew}
                  >
                    {savingNew ? (
                      <Loader2 size={16} className="animate-spin" />
                    ) : saved ? (
                      <CheckCircle2 size={16} />
                    ) : (
                      <Sprout size={16} />
                    )}
                    {savingNew
                      ? "Saving..."
                      : saved
                        ? "Saved!"
                        : "Save listing"}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {editing && (
        <div className="fixed inset-0 z-50 grid place-items-center overflow-y-auto bg-slate-900/60 p-4 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-xl rounded-2xl border-2 border-slate-100 bg-white shadow-strong max-h-[90vh] overflow-hidden">
            <div className="p-6 overflow-y-auto max-h-[90vh]">
              <h3 className="font-display text-xl font-extrabold text-slate-900">
                Edit Listing
              </h3>
              <p className="text-sm text-slate-500 mt-1">
                Update details visible in the marketplace.
              </p>
              <div className="mt-4 grid sm:grid-cols-2 gap-3">
                <div>
                  <label className="label">Crop</label>
                  <input
                    className="input"
                    value={editing.crop}
                    onChange={(e) =>
                      setEditing((v) => ({ ...v, crop: e.target.value }))
                    }
                  />
                </div>
                <div>
                  <label className="label">Variety</label>
                  <input
                    className="input"
                    value={editing.variety}
                    onChange={(e) =>
                      setEditing((v) => ({ ...v, variety: e.target.value }))
                    }
                  />
                </div>
                <div>
                  <label className="label">Expected yield (kg)</label>
                  <input
                    type="number"
                    min={0}
                    className="input"
                    value={editing.expectedYieldKg}
                    onChange={(e) =>
                      setEditing((v) => ({
                        ...v,
                        expectedYieldKg: e.target.value,
                      }))
                    }
                  />
                </div>
                <div>
                  <label className="label">Pre-order stock (kg)</label>
                  <input
                    type="number"
                    min={0}
                    className="input"
                    value={editing.preOrderStockKg}
                    onChange={(e) =>
                      setEditing((v) => ({
                        ...v,
                        preOrderStockKg: e.target.value,
                      }))
                    }
                  />
                </div>
                <div className="sm:col-span-2 rounded-xl border border-slate-200 bg-slate-50 p-3">
                  <label className="inline-flex items-center gap-2 text-sm font-semibold text-slate-700">
                    <input
                      type="checkbox"
                      className="h-4 w-4 rounded border-slate-300"
                      checked={!!editing.allowBulkPreorder}
                      onChange={(e) =>
                        setEditing((v) => ({
                          ...v,
                          allowBulkPreorder: e.target.checked,
                        }))
                      }
                    />
                    Allow bulk pre-order (first come, first served)
                  </label>
                  {!editing.allowBulkPreorder && (
                    <div className="mt-2">
                      <label className="label">
                        Max pre-order per account (kg)
                      </label>
                      <input
                        type="number"
                        min={1}
                        className="input"
                        value={editing.maxPerAccountKg}
                        onChange={(e) =>
                          setEditing((v) => ({
                            ...v,
                            maxPerAccountKg: e.target.value,
                          }))
                        }
                      />
                    </div>
                  )}
                </div>
                <div>
                  <label className="label">Price per kg (PHP)</label>
                  <input
                    type="number"
                    min={0}
                    className="input"
                    value={editing.pricePerKg}
                    onChange={(e) =>
                      setEditing((v) => ({ ...v, pricePerKg: e.target.value }))
                    }
                  />
                </div>
                <div>
                  <label className="label">Estimated harvest</label>
                  <input
                    type="date"
                    className="input"
                    value={editing.estimatedHarvest}
                    onChange={(e) =>
                      setEditing((v) => ({
                        ...v,
                        estimatedHarvest: e.target.value,
                      }))
                    }
                  />
                </div>
                <div className="sm:col-span-2">
                  <label className="label">Notes</label>
                  <textarea
                    rows={3}
                    className="input"
                    value={editing.notes}
                    onChange={(e) =>
                      setEditing((v) => ({ ...v, notes: e.target.value }))
                    }
                  />
                </div>
                <div className="sm:col-span-2">
                  <ImageUpload
                    label="Crop photo"
                    folder="crops"
                    aspect="aspect-[16/8]"
                    value={editing.photo}
                    onChange={(photo) => setEditing((v) => ({ ...v, photo }))}
                  />
                </div>
              </div>
              <div className="mt-5 flex items-center justify-end gap-2">
                <button className="btn-ghost" onClick={() => setEditing(null)}>
                  Cancel
                </button>
                <button
                  className="btn-primary px-5 py-2.5"
                  onClick={saveEdit}
                  disabled={savingEdit}
                >
                  {savingEdit ? (
                    <Loader2 size={16} className="animate-spin" />
                  ) : (
                    <CheckCircle2 size={16} />
                  )}
                  {savingEdit ? "Saving..." : "Save changes"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      <PromptModal
        open={!!renewPrompt}
        title={
          renewPrompt ? `Renew ${renewPrompt.planting.crop}` : "Renew listing"
        }
        message="Add how many kg of pre-order stock?"
        error={renewPrompt?.error || ""}
        label="Additional stock (kg)"
        inputType="number"
        value={renewPrompt?.value || ""}
        onChange={(value) =>
          setRenewPrompt((prev) =>
            prev ? { ...prev, value, error: "" } : prev,
          )
        }
        confirmLabel="Add stock"
        cancelLabel="Cancel"
        onClose={() => setRenewPrompt(null)}
        onConfirm={async () => {
          if (!renewPrompt) return;
          const addedKg = Number(renewPrompt.value);
          if (!Number.isFinite(addedKg) || addedKg <= 0) {
            setRenewPrompt((prev) =>
              prev ? { ...prev, error: "Enter a valid stock amount." } : prev,
            );
            return;
          }
          setFormError("");
          setFormMessage("");
          try {
            await db.updatePlanting(renewPrompt.planting.id, {
              preOrderStockKg: renewPrompt.currentStock + addedKg,
            });
            setFormMessage(
              `${renewPrompt.planting.crop} renewed with ${addedKg} kg additional stock.`,
            );
            setRenewPrompt(null);
          } catch (e) {
            setFormError(e?.message || "Failed to renew listing.");
          }
        }}
      />
    </div>
  );
}
