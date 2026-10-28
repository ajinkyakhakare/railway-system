// Small coloured label. tone: green | yellow | red | blue | gray
const TONES = {
  green: 'bg-green-100 text-green-800',
  yellow: 'bg-yellow-100 text-yellow-800',
  red: 'bg-red-100 text-red-800',
  blue: 'bg-blue-100 text-blue-800',
  gray: 'bg-slate-100 text-slate-700',
};

export function Badge({ tone = 'gray', children }) {
  const look = TONES[tone] || TONES.gray;
  return (
    <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${look}`}>
      {children}
    </span>
  );
}
