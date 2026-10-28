// White panel with an optional title and an optional actions area (buttons) in the header.
export function Card({ title, actions, className = '', children }) {
  const hasHeader = Boolean(title) || Boolean(actions);

  return (
    <section className={`rounded-lg border border-slate-200 bg-white shadow-sm ${className}`}>
      {hasHeader && (
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-200 px-4 py-3">
          {title ? <h2 className="text-base font-semibold text-slate-900">{title}</h2> : <span />}
          {actions && <div className="flex items-center gap-2">{actions}</div>}
        </div>
      )}
      <div className="p-4">{children}</div>
    </section>
  );
}
