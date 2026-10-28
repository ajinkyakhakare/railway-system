// Display helpers shared by all modules.
// Dates and times coming from the backend have no time zone (LocalDate / LocalTime /
// LocalDateTime), so they are formatted by reading the text, not through Date objects.
// That way the value never shifts because of the browser's time zone.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const EMPTY = '—';

const pad2 = (n) => String(n).padStart(2, '0');

// 1234.5 -> "₹1,234.50"
export function formatMoney(n) {
  if (n === null || n === undefined || n === '') return EMPTY;
  const value = Number(n);
  if (!Number.isFinite(value)) return EMPTY;
  const text = Math.abs(value).toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return (value < 0 ? '-' : '') + '₹' + text;
}

// "2026-10-27" (or "2026-10-27T06:00:00") -> "27 Oct 2026"
export function formatDate(value) {
  if (!value) return EMPTY;
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value));
  if (!match) return String(value);
  const [, year, month, day] = match;
  const monthName = MONTHS[Number(month) - 1];
  return monthName ? `${day} ${monthName} ${year}` : String(value);
}

// "06:00:00" -> "06:00"
export function formatTime(value) {
  if (!value) return EMPTY;
  const match = /^(\d{2}):(\d{2})/.exec(String(value));
  return match ? `${match[1]}:${match[2]}` : String(value);
}

// "2026-10-27T06:00:00" -> "27 Oct 2026, 06:00"
export function formatDateTime(iso) {
  if (!iso) return EMPTY;
  const parts = String(iso).split(/[T ]/);
  const datePart = formatDate(parts[0]);
  if (parts.length < 2) return datePart;
  return `${datePart}, ${formatTime(parts[1])}`;
}

// Today's date in the browser's local time as "yyyy-MM-dd" (toISOString would use UTC).
export function todayISO() {
  const now = new Date();
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
}
