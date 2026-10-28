// Task G1.5 | Group G1 (Train, Station & Route) | Admin page: manage trains (/admin/trains, role ADMIN).
//
// - Table of all trains.
// - Form to create a train (number, name, type, route, run days Mon..Sun).
// - Per-row actions: "Add coaches" (generates seats on the server) and "Generate runs" (creates dated runs).
// Server answers (counts) are shown in a success Alert.

import { useState } from 'react';
import { useAsync } from '@/hooks/useAsync';
import { Alert, Badge, Button, Card, Input, Modal, PageHeader, Select, Spinner, Table } from '@/components/ui';
import { todayISO } from '@/utils/format';
import {
  addCoaches,
  createTrain,
  fetchCoachTypes,
  fetchRoutes,
  fetchTrains,
  generateRuns,
} from '../api';

const TRAIN_TYPES = ['EXPRESS', 'SUPERFAST', 'RAJDHANI', 'SHATABDI', 'LOCAL'];

// ISO weekday numbers: 1 = Monday ... 7 = Sunday (same as the database).
const WEEKDAYS = [
  { value: 1, label: 'Mon' },
  { value: 2, label: 'Tue' },
  { value: 3, label: 'Wed' },
  { value: 4, label: 'Thu' },
  { value: 5, label: 'Fri' },
  { value: 6, label: 'Sat' },
  { value: 7, label: 'Sun' },
];

const ALL_DAYS = WEEKDAYS.map((d) => d.value);

// The server limits a generation request to 60 days.
const MAX_RUN_RANGE_DAYS = 60;

// ------------------------------------------------------------ date helpers

/** Date -> "yyyy-MM-dd" using LOCAL date parts (toISOString would shift to UTC). */
function toIsoDate(date) {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

/** "2026-10-28" + 14 -> "2026-11-11" */
function addDays(isoDate, days) {
  const date = new Date(`${isoDate}T00:00:00`);
  date.setDate(date.getDate() + days);
  return toIsoDate(date);
}

/** Whole days from one ISO date to another. */
function daysBetween(fromIso, toIso) {
  const from = new Date(`${fromIso}T00:00:00`);
  const to = new Date(`${toIso}T00:00:00`);
  return Math.round((to - from) / 86400000);
}

// ------------------------------------------------------------ data loading

/** Trains, routes and coach types are all needed by this page. */
async function loadPageData() {
  const [trains, routes, coachTypes] = await Promise.all([fetchTrains(), fetchRoutes(), fetchCoachTypes()]);
  return { trains, routes, coachTypes };
}

// -------------------------------------------------------- create-train form

function CreateTrainForm({ routes, onCreated, onCancel }) {
  const [trainNo, setTrainNo] = useState('');
  const [trainName, setTrainName] = useState('');
  const [trainType, setTrainType] = useState('EXPRESS');
  const [routeId, setRouteId] = useState('');
  const [runDays, setRunDays] = useState(ALL_DAYS);
  const [errors, setErrors] = useState({});
  const [serverError, setServerError] = useState('');
  const [saving, setSaving] = useState(false);

  const routeOptions = routes.map((r) => ({ value: String(r.routeId), label: r.routeName }));
  const typeOptions = TRAIN_TYPES.map((t) => ({ value: t, label: t }));

  /** Returns an object with one message per invalid field (empty object = valid). */
  function validate() {
    const found = {};
    if (!/^[0-9]{5}$/.test(trainNo)) {
      found.trainNo = 'Train number must be exactly 5 digits.';
    }
    if (!trainName.trim()) {
      found.trainName = 'Train name is required.';
    }
    if (!routeId) {
      found.routeId = 'Select a route.';
    }
    if (runDays.length === 0) {
      found.runDays = 'Select at least one running day.';
    }
    return found;
  }

  function toggleDay(day) {
    setRunDays((current) =>
      current.includes(day) ? current.filter((d) => d !== day) : [...current, day].sort((a, b) => a - b)
    );
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setServerError('');

    const found = validate();
    setErrors(found);
    if (Object.keys(found).length > 0) {
      return;
    }

    setSaving(true);
    try {
      const result = await createTrain({
        trainNo,
        trainName: trainName.trim(),
        trainType,
        routeId: Number(routeId),
        runDays,
      });
      onCreated(result.trainId);
    } catch (err) {
      setServerError(err.message || 'Could not create the train.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card title="Create a train">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid gap-4 md:grid-cols-2">
          <Input
            label="Train number"
            name="trainNo"
            value={trainNo}
            onChange={(e) => setTrainNo(e.target.value)}
            error={errors.trainNo}
            placeholder="5 digits, e.g. 12345"
            maxLength={5}
            required
          />
          <Input
            label="Train name"
            name="trainName"
            value={trainName}
            onChange={(e) => setTrainName(e.target.value)}
            error={errors.trainName}
            placeholder="e.g. Sahyadri Express"
            maxLength={80}
            required
          />
          <Select
            label="Train type"
            name="trainType"
            value={trainType}
            onChange={(e) => setTrainType(e.target.value)}
            options={typeOptions}
          />
          <Select
            label="Route"
            name="routeId"
            value={routeId}
            onChange={(e) => setRouteId(e.target.value)}
            options={routeOptions}
            placeholder="Select route"
            error={errors.routeId}
          />
        </div>

        {/* Run days: one checkbox per weekday. */}
        <fieldset>
          <legend className="mb-1 text-sm font-medium text-gray-700">Runs on</legend>
          <div className="flex flex-wrap gap-4">
            {WEEKDAYS.map((day) => (
              <label key={day.value} className="inline-flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={runDays.includes(day.value)}
                  onChange={() => toggleDay(day.value)}
                  className="h-4 w-4 rounded border-gray-300"
                />
                {day.label}
              </label>
            ))}
          </div>
          {errors.runDays && <p className="mt-1 text-sm text-red-600">{errors.runDays}</p>}
        </fieldset>

        {serverError && <Alert tone="error">{serverError}</Alert>}

        <div className="flex gap-2">
          <Button type="submit" loading={saving}>
            Create train
          </Button>
          <Button variant="secondary" onClick={onCancel} disabled={saving}>
            Cancel
          </Button>
        </div>
      </form>
    </Card>
  );
}

// -------------------------------------------------------- add-coaches modal

function AddCoachesModal({ train, coachTypes, onClose, onDone }) {
  const [coachTypeId, setCoachTypeId] = useState('');
  const [coachCount, setCoachCount] = useState('1');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  const typeOptions = coachTypes.map((t) => ({
    value: String(t.coachTypeId),
    label: `${t.className} (${t.classCode}) - ${t.seatsPerCoach} seats per coach`,
  }));

  async function handleSubmit(event) {
    event.preventDefault();
    setError('');

    const count = Number(coachCount);
    if (!coachTypeId) {
      setError('Select a coach type.');
      return;
    }
    if (!Number.isInteger(count) || count < 1 || count > 20) {
      setError('Number of coaches must be a whole number from 1 to 20.');
      return;
    }

    setSaving(true);
    try {
      const result = await addCoaches(train.trainId, { coachTypeId: Number(coachTypeId), coachCount: count });
      onDone(
        `Train ${train.trainNo}: added ${result.coachesAdded} coach(es) with ${result.seatsAdded} seats.`
      );
      onClose();
    } catch (err) {
      setError(err.message || 'Could not add coaches.');
      setSaving(false);
    }
  }

  return (
    <Modal open title={`Add coaches - ${train.trainNo} ${train.trainName}`} onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <Select
          label="Coach type"
          name="coachTypeId"
          value={coachTypeId}
          onChange={(e) => setCoachTypeId(e.target.value)}
          options={typeOptions}
          placeholder="Select coach type"
        />
        <Input
          label="Number of coaches"
          name="coachCount"
          type="number"
          min={1}
          max={20}
          value={coachCount}
          onChange={(e) => setCoachCount(e.target.value)}
        />
        <p className="text-sm text-gray-500">Seats are generated automatically for every new coach.</p>

        {error && <Alert tone="error">{error}</Alert>}

        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            Add coaches
          </Button>
        </div>
      </form>
    </Modal>
  );
}

// ------------------------------------------------------ generate-runs modal

function GenerateRunsModal({ train, onClose, onDone }) {
  const [fromDate, setFromDate] = useState(todayISO());
  const [toDate, setToDate] = useState(addDays(todayISO(), 14));
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  async function handleSubmit(event) {
    event.preventDefault();
    setError('');

    if (!fromDate || !toDate) {
      setError('Select both dates.');
      return;
    }
    const span = daysBetween(fromDate, toDate);
    if (span < 0) {
      setError('The end date must not be before the start date.');
      return;
    }
    if (span > MAX_RUN_RANGE_DAYS) {
      setError(`The date range cannot be longer than ${MAX_RUN_RANGE_DAYS} days.`);
      return;
    }

    setSaving(true);
    try {
      const result = await generateRuns(train.trainId, { fromDate, toDate });
      onDone(`Train ${train.trainNo}: ${result.runsCreated} new run(s) created.`);
      onClose();
    } catch (err) {
      setError(err.message || 'Could not generate runs.');
      setSaving(false);
    }
  }

  return (
    <Modal open title={`Generate runs - ${train.trainNo} ${train.trainName}`} onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Input
            label="From date"
            name="fromDate"
            type="date"
            value={fromDate}
            onChange={(e) => setFromDate(e.target.value)}
          />
          <Input
            label="To date"
            name="toDate"
            type="date"
            value={toDate}
            onChange={(e) => setToDate(e.target.value)}
          />
        </div>
        <p className="text-sm text-gray-500">
          A run is created for every date in the range on which the train is scheduled. Dates that already
          have a run are skipped. Add the coaches first, otherwise the new runs have no seats.
        </p>

        {error && <Alert tone="error">{error}</Alert>}

        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            Generate runs
          </Button>
        </div>
      </form>
    </Modal>
  );
}

// -------------------------------------------------------------------- page

export default function AdminTrainsPage() {
  const pageState = useAsync(loadPageData, []);
  const [showForm, setShowForm] = useState(false);
  const [message, setMessage] = useState(null); // {tone, text} shown at the top
  const [modal, setModal] = useState(null);     // {type: 'coaches' | 'runs', train}

  const trains = pageState.data ? pageState.data.trains : [];
  const routes = pageState.data ? pageState.data.routes : [];
  const coachTypes = pageState.data ? pageState.data.coachTypes : [];

  function handleCreated(trainId) {
    setShowForm(false);
    setMessage({
      tone: 'success',
      text: `Train created (id ${trainId}). Next: add coaches, then generate runs.`,
    });
    pageState.reload();
  }

  function handleActionDone(text) {
    setMessage({ tone: 'success', text });
  }

  const columns = [
    { key: 'trainNo', header: 'Train no' },
    { key: 'trainName', header: 'Name' },
    { key: 'trainType', header: 'Type', render: (row) => <Badge tone="blue">{row.trainType}</Badge> },
    { key: 'routeName', header: 'Route' },
    {
      key: 'isActive',
      header: 'Status',
      render: (row) =>
        row.isActive ? <Badge tone="green">Active</Badge> : <Badge tone="gray">Inactive</Badge>,
    },
    {
      key: 'actions',
      header: 'Actions',
      render: (row) => (
        <div className="flex flex-wrap gap-2">
          <Button variant="secondary" onClick={() => setModal({ type: 'coaches', train: row })}>
            Add coaches
          </Button>
          <Button variant="secondary" onClick={() => setModal({ type: 'runs', train: row })}>
            Generate runs
          </Button>
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Manage trains"
        subtitle="Create trains, add coaches and generate the dated runs passengers can book."
        actions={
          !showForm && (
            <Button
              onClick={() => {
                setMessage(null);
                setShowForm(true);
              }}
            >
              New train
            </Button>
          )
        }
      />

      {message && <Alert tone={message.tone}>{message.text}</Alert>}

      {pageState.error && <Alert tone="error">{pageState.error.message}</Alert>}

      {pageState.loading && !pageState.data && <Spinner />}

      {showForm && pageState.data && (
        <CreateTrainForm routes={routes} onCreated={handleCreated} onCancel={() => setShowForm(false)} />
      )}

      {pageState.data && (
        <Card title="All trains">
          <Table columns={columns} rows={trains} rowKey="trainId" emptyText="No trains yet. Create the first one." />
        </Card>
      )}

      {modal && modal.type === 'coaches' && (
        <AddCoachesModal
          train={modal.train}
          coachTypes={coachTypes}
          onClose={() => setModal(null)}
          onDone={handleActionDone}
        />
      )}

      {modal && modal.type === 'runs' && (
        <GenerateRunsModal train={modal.train} onClose={() => setModal(null)} onDone={handleActionDone} />
      )}
    </div>
  );
}
