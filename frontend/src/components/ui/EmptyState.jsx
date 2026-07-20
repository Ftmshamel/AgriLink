export default function EmptyState({ icon: Icon, title, description, action }) {
  return (
    <div className="card p-6 sm:p-7 text-center">
      {Icon && (
        <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-brand-50 text-brand-600">
          <Icon size={26} />
        </div>
      )}
      <h3 className="mt-4 text-lg font-semibold text-slate-900">{title}</h3>
      {description && <p className="mt-1 text-sm text-slate-500">{description}</p>}
      {action && <div className="mt-5 flex justify-center">{action}</div>}
    </div>
  );
}
