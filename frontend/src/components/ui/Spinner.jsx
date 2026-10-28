// Centered loading indicator.
export function Spinner() {
  return (
    <div role="status" className="flex items-center justify-center py-8">
      <span
        className="h-8 w-8 animate-spin rounded-full border-4 border-indigo-200 border-t-indigo-700"
        aria-hidden="true"
      />
      <span className="sr-only">Loading…</span>
    </div>
  );
}
