export default function Logo({ className = "", showText = true, light = false }) {
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <img
        src="/logo.png"
        alt="AgriLink logo"
        className="h-9 w-9 rounded-xl object-contain"
      />
      {showText && (
        <span className={`font-display font-extrabold text-xl tracking-tight ${light ? "text-white" : "text-slate-900"}`}>
          Agri<span className={light ? "text-brand-300" : "text-brand-600"}>Link</span>
        </span>
      )}
    </div>
  );
}
