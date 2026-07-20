const TONES = {
  brand:   { icon: "bg-brand-600 text-white",   bar: "bg-brand-600" },
  harvest: { icon: "bg-harvest-500 text-white",  bar: "bg-harvest-500" },
  blue:    { icon: "bg-blue-600 text-white",     bar: "bg-blue-600" },
  rose:    { icon: "bg-rose-600 text-white",     bar: "bg-rose-600" },
};

export default function Stat({ icon: Icon, label, value, sublabel, tone = "brand" }) {
  const t = TONES[tone] || TONES.brand;
  return (
    <div className="card overflow-hidden flex flex-col">
      {/* Colored top bar */}
      <div className={`h-1.5 w-full ${t.bar}`} />
      <div className="p-5 flex items-start gap-4">
        <div className={`grid h-12 w-12 shrink-0 place-items-center rounded-xl ${t.icon}`}>
          {Icon ? <Icon size={22} /> : null}
        </div>
        <div className="min-w-0">
          <div className="text-xs font-bold uppercase tracking-widest text-slate-400">{label}</div>
          <div className="mt-1 font-display text-2xl font-extrabold text-slate-900">{value}</div>
          {sublabel && <div className="mt-1 text-xs text-slate-500">{sublabel}</div>}
        </div>
      </div>
    </div>
  );
}
