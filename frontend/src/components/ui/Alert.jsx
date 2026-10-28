// Message box. tone: error | success | info
const TONES = {
  error: 'border-red-300 bg-red-50 text-red-800',
  success: 'border-green-300 bg-green-50 text-green-800',
  info: 'border-blue-300 bg-blue-50 text-blue-800',
};

export function Alert({ tone = 'info', children }) {
  const look = TONES[tone] || TONES.info;
  // Errors are announced immediately by screen readers; other messages politely.
  const role = tone === 'error' ? 'alert' : 'status';
  return (
    <div role={role} className={`rounded-md border px-4 py-3 text-sm ${look}`}>
      {children}
    </div>
  );
}
