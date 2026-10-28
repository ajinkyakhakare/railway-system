// G5 - Update Status (OPERATOR and ADMIN).
// Flow: choose a train -> choose a run (journey date) -> edit the status form -> PUT /ops/status/{runId}.
// The database trigger trg_status_flag may change the status by itself (for example a delay of
// 15 minutes or more turns SCHEDULED / ON_TIME into DELAYED), so the page shows the status that
// the server really saved.
import { useEffect, useState } from 'react';
import { useAsync } from '@/hooks/useAsync';
import { formatDate, formatDateTime } from '@/utils/format';
import { Alert, Button, Card, Input, PageHeader, Select, StatusBadge } from '@/components/ui';
import { getRunStatus, getStations, getTrainRuns, getTrains, updateRunStatus } from '../api.js';

const STATUS_OPTIONS = ['SCHEDULED', 'ON_TIME', 'DELAYED', 'CANCELLED', 'ARRIVED'].map((s) => ({
  value: s,
  label: s,
}));

const EMPTY_FORM = { status: 'SCHEDULED', delayMinutes: '0', currentStationId: '', reason: '' };

// Date as yyyy-MM-dd, moved by a number of days from today (negative = past).
function dateFromToday(days) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export default function StatusUpdatePage() {
  const [trainId, setTrainId] = useState('');
  const [runId, setRunId] = useState('');
  const [form, setForm] = useState(EMPTY_FORM);
  const [errors, setErrors] = useState({});
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [result, setResult] = useState(null); // answer of the last successful update

  // Reference data for the drop-downs.
  const trains = useAsync(() => getTrains(), []);
  const stations = useAsync(() => getStations(), []);

  // Runs of the chosen train: from 2 days ago (night trains) to 30 days ahead.
  const runs = useAsync(
    () => (trainId ? getTrainRuns(trainId, dateFromToday(-2), dateFromToday(30)) : Promise.resolve([])),
    [trainId]
  );

  // Current status of the chosen run, used to pre-fill the form.
  const current = useAsync(() => (runId ? getRunStatus(runId) : Promise.resolve(null)), [runId]);

  // Whenever the current status is loaded (or reloaded after saving) copy it into the form.
  useEffect(() => {
    if (!current.data) return;
    const row = Array.isArray(current.data) ? current.data[0] : current.data;
    if (!row) return;
    setForm({
      status: row.status || 'SCHEDULED',
      delayMinutes: String(row.delayMinutes ?? 0),
      currentStationId: row.currentStationId ? String(row.currentStationId) : '',
      reason: row.lastReason || '',
    });
  }, [current.data]);

  const trainOptions = (trains.data || []).map((t) => ({
    value: String(t.trainId),
    label: `${t.trainNo} - ${t.trainName}`,
  }));

  const runOptions = (runs.data || []).map((r) => ({
    value: String(r.runId),
    label: formatDate(r.journeyDate),
  }));

  // First option means "train is not at a station right now" (sent as null).
  const stationOptions = [
    { value: '', label: 'Not at a station' },
    ...(stations.data || []).map((s) => ({
      value: String(s.stationId),
      label: `${s.stationName} (${s.stationCode})`,
    })),
  ];

  function handleTrainChange(event) {
    setTrainId(event.target.value);
    setRunId('');
    setForm(EMPTY_FORM);
    setErrors({});
    setResult(null);
    setSubmitError('');
  }

  function handleRunChange(event) {
    setRunId(event.target.value);
    setForm(EMPTY_FORM);
    setErrors({});
    setResult(null);
    setSubmitError('');
  }

  function handleFieldChange(event) {
    const { name, value } = event.target;
    setForm((old) => ({ ...old, [name]: value }));
  }

  // Returns an object with one message per invalid field (empty object = valid).
  function validate() {
    const found = {};
    if (!runId) found.runId = 'Please choose a run';
    if (!form.status) found.status = 'Please choose a status';
    if (!/^\d+$/.test(String(form.delayMinutes).trim())) {
      found.delayMinutes = 'Enter a whole number, 0 or more';
    }
    if (form.reason.length > 100) found.reason = 'Reason can have at most 100 characters';
    return found;
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setResult(null);
    setSubmitError('');

    const found = validate();
    setErrors(found);
    if (Object.keys(found).length > 0) return;

    setSubmitting(true);
    try {
      const saved = await updateRunStatus(runId, {
        status: form.status,
        delayMinutes: Number(form.delayMinutes),
        currentStationId: form.currentStationId ? Number(form.currentStationId) : null,
        reason: form.reason.trim() === '' ? null : form.reason.trim(),
      });
      setResult({ ...saved, requestedStatus: form.status });
      current.reload(); // refresh the form with what the database really holds
    } catch (err) {
      setSubmitError(err.message || 'Could not update the status');
    } finally {
      setSubmitting(false);
    }
  }

  const loadError = trains.error || stations.error || runs.error || current.error;
  const autoChanged = result && result.status !== result.requestedStatus;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Update Train Status"
        subtitle="Record delays, current position and status of a train run"
      />

      {loadError && <Alert tone="error">{loadError.message}</Alert>}

      <Card title="1. Choose the run">
        <div className="grid gap-4 md:grid-cols-2">
          <Select
            label="Train"
            name="trainId"
            value={trainId}
            onChange={handleTrainChange}
            options={trainOptions}
            placeholder={trains.loading ? 'Loading trains...' : 'Select a train'}
          />
          <Select
            label="Run (journey date)"
            name="runId"
            value={runId}
            onChange={handleRunChange}
            options={runOptions}
            error={errors.runId}
            placeholder={
              !trainId ? 'Select a train first' : runs.loading ? 'Loading runs...' : 'Select a date'
            }
          />
        </div>
        {trainId && !runs.loading && runOptions.length === 0 && (
          <p className="mt-3 text-sm text-gray-500">This train has no runs in the selected period.</p>
        )}
      </Card>

      {runId && (
        <Card title="2. New status">
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="grid gap-4 md:grid-cols-2">
              <Select
                label="Status"
                name="status"
                value={form.status}
                onChange={handleFieldChange}
                options={STATUS_OPTIONS}
                error={errors.status}
              />
              <Input
                label="Delay (minutes)"
                name="delayMinutes"
                type="number"
                min="0"
                value={form.delayMinutes}
                onChange={handleFieldChange}
                error={errors.delayMinutes}
              />
              <Select
                label="Current station"
                name="currentStationId"
                value={form.currentStationId}
                onChange={handleFieldChange}
                options={stationOptions}
              />
              <Input
                label="Reason"
                name="reason"
                value={form.reason}
                onChange={handleFieldChange}
                error={errors.reason}
                placeholder="For example: signal failure near Kalyan"
                maxLength={100}
              />
            </div>

            <p className="text-sm text-gray-500">
              Note: a delay of 15 minutes or more automatically marks a scheduled / on-time train as
              DELAYED, and a delay of 0 changes DELAYED back to ON_TIME.
            </p>

            {submitError && <Alert tone="error">{submitError}</Alert>}

            <Button type="submit" loading={submitting}>
              Save status
            </Button>
          </form>
        </Card>
      )}

      {result && (
        <Alert tone="success">
          <div className="space-y-1">
            <p className="flex items-center gap-2">
              Status saved: <StatusBadge status={result.status} />, delay {result.delayMinutes} min
              (at {formatDateTime(result.updatedAt)}).
            </p>
            {autoChanged && (
              <p>
                The system changed the status from {result.requestedStatus} to {result.status}{' '}
                automatically, based on the delay minutes.
              </p>
            )}
          </div>
        </Alert>
      )}
    </div>
  );
}
