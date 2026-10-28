// Friendly "nothing here" box.
export function EmptyState({ message = 'Nothing to show yet.' }) {
  return (
    <div className="rounded-lg border border-dashed border-slate-300 bg-white px-4 py-10 text-center text-sm text-slate-500">
      {message}
    </div>
  );
}
