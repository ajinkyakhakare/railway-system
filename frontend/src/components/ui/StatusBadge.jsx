// Badge whose colour is chosen from a status text (booking, payment, seat or train status).
import { Badge } from './Badge.jsx';

const STATUS_TONES = {
  // green: good / done
  CNF: 'green',
  CONFIRMED: 'green',
  SUCCESS: 'green',
  ON_TIME: 'green',
  // yellow: waiting / needs attention
  RAC: 'yellow',
  PENDING_PAYMENT: 'yellow',
  SCHEDULED: 'yellow',
  DELAYED: 'yellow',
  // blue: informational
  WL: 'blue',
  CREATED: 'blue',
  // red: stopped / failed
  CANCELLED: 'red',
  FAILED: 'red',
  EXPIRED: 'red',
  // gray: finished
  ARRIVED: 'gray',
};

export function StatusBadge({ status }) {
  if (!status) return <Badge tone="gray">—</Badge>;
  const key = String(status).toUpperCase();
  const tone = STATUS_TONES[key] || 'gray';
  // "PENDING_PAYMENT" is displayed as "PENDING PAYMENT"
  return <Badge tone={tone}>{String(status).replace(/_/g, ' ')}</Badge>;
}
