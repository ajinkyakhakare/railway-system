// Task G1.5 | Group G1 (Train, Station & Route) | Admin page: routes and their stops (/admin/routes, role ADMIN).
//
// - Table of routes with a "View stops" button (opens a modal with the stop list).
// - Form to create a route with a dynamic list of stops (add / remove rows).
//
// How the stop list works in the form:
//   * the FIRST row is always the source station and the LAST row is always the destination
//     (their stations come from the two selects above, so they cannot disagree);
//   * "Add stop" inserts a new intermediate row just before the destination;
//   * stopSeq is not typed by the user: it is the position of the row (1, 2, 3 ...).

import { useState } from 'react';
import { useAsync } from '@/hooks/useAsync';
import { Alert, Button, Card, Input, Modal, PageHeader, Select, Spinner, Table } from '@/components/ui';
import { formatTime } from '@/utils/format';
import { createRoute, fetchRouteStops, fetchRoutes, fetchStations } from '../api';

// --------------------------------------------------------------- helpers

/** Shows "06:00" or a dash when the time is missing. */
function showTime(value) {
  return value ? formatTime(value) : '—';
}

/** "06:00" (from <input type="time">) -> "06:00:00"; empty -> null. The API expects HH:mm:ss. */
function toApiTime(value) {
  if (!value) {
    return null;
  }
  return value.length === 5 ? `${value}:00` : value;
}

// Counter that gives every form row a stable React key (rows can be removed from the middle).
let nextRowKey = 1;

function newStopRow() {
  const row = {
    key: nextRowKey,
    stationId: '',
    arrivalTime: '',
    departureTime: '',
    dayOffset: '0',
    distance: '',
  };
  nextRowKey += 1;
  return row;
}

/** A new form always starts with two rows: source and destination. */
function initialStops() {
  return [newStopRow(), newStopRow()];
}

/**
 * Station of a row: the first row is the source, the last row is the destination,
 * every row in between uses its own selected station.
 */
function stationIdOfRow(index, stops, sourceId, destId) {
  if (index === 0) {
    return sourceId;
  }
  if (index === stops.length - 1) {
    return destId;
  }
  return stops[index].stationId;
}

/**
 * Checks the whole form. Returns the first problem as text, or '' when everything is valid.
 * (The server validates again; this only gives quicker feedback.)
 */
function validateRoute(routeName, sourceId, destId, stops) {
  if (!routeName.trim()) {
    return 'Route name is required.';
  }
  if (routeName.trim().length > 100) {
    return 'Route name can have at most 100 characters.';
  }
  if (!sourceId || !destId) {
    return 'Select the source and destination stations.';
  }
  if (sourceId === destId) {
    return 'Source and destination must be different stations.';
  }

  const lastIndex = stops.length - 1;
  const usedStations = new Set();
  let previousDay = 0;
  let previousKm = -1;

  for (let i = 0; i < stops.length; i += 1) {
    const stop = stops[i];
    const label = `Stop ${i + 1}`;
    const stationId = stationIdOfRow(i, stops, sourceId, destId);

    if (!stationId) {
      return `${label}: select a station.`;
    }
    if (usedStations.has(stationId)) {
      return `${label}: a station can appear only once in a route.`;
    }
    usedStations.add(stationId);

    // Times: the source only departs, the destination only arrives, other stops do both.
    if (i !== 0 && !stop.arrivalTime) {
      return `${label}: arrival time is required.`;
    }
    if (i !== lastIndex && !stop.departureTime) {
      return `${label}: departure time is required.`;
    }
    // Same rule as database trigger trg_route_stop_bi: a halt never crosses midnight.
    if (i !== 0 && i !== lastIndex && stop.departureTime < stop.arrivalTime) {
      return `${label}: departure time cannot be before arrival time.`;
    }

    // Day offset = days since the train started (0 = same day as the start).
    const day = i === 0 ? 0 : Number(stop.dayOffset);
    if (!Number.isInteger(day) || day < 0 || day > 3) {
      return `${label}: day offset must be a whole number from 0 to 3.`;
    }
    if (day < previousDay) {
      return `${label}: day offset cannot be smaller than the previous stop.`;
    }
    previousDay = day;

    // Distance from the source station: the source is 0 km, then strictly increasing.
    const km = i === 0 ? 0 : Number(stop.distance);
    if (stop.distance === '' && i !== 0) {
      return `${label}: distance from source is required.`;
    }
    if (!Number.isInteger(km) || km < 0) {
      return `${label}: distance must be a whole number of km, 0 or more.`;
    }
    if (km <= previousKm) {
      return `${label}: distance must be greater than the previous stop.`;
    }
    previousKm = km;
  }
  return '';
}

// ------------------------------------------------------ stops modal (view)

function RouteStopsModal({ route, onClose }) {
  const stopsState = useAsync(() => fetchRouteStops(route.routeId), [route.routeId]);

  const columns = [
    { key: 'stopSeq', header: 'Seq' },
    { key: 'stationName', header: 'Station', render: (row) => `${row.stationName} (${row.stationCode})` },
    { key: 'arrivalTime', header: 'Arrival', render: (row) => showTime(row.arrivalTime) },
    { key: 'departureTime', header: 'Departure', render: (row) => showTime(row.departureTime) },
    { key: 'dayOffset', header: 'Day', render: (row) => `Day ${Number(row.dayOffset) + 1}` },
    { key: 'distanceFromSourceKm', header: 'Km', render: (row) => `${row.distanceFromSourceKm} km` },
  ];

  return (
    <Modal open title={`Stops - ${route.routeName}`} onClose={onClose}>
      <div className="space-y-4">
        {stopsState.loading && !stopsState.data && <Spinner />}
        {stopsState.error && <Alert tone="error">{stopsState.error.message}</Alert>}
        {stopsState.data && (
          <Table columns={columns} rows={stopsState.data} rowKey="routeStopId" emptyText="This route has no stops." />
        )}
        <div className="flex justify-end">
          <Button variant="secondary" onClick={onClose}>
            Close
          </Button>
        </div>
      </div>
    </Modal>
  );
}

// ------------------------------------------------------- create-route form

function CreateRouteForm({ stations, onCreated, onCancel }) {
  const [routeName, setRouteName] = useState('');
  const [sourceId, setSourceId] = useState('');
  const [destId, setDestId] = useState('');
  const [stops, setStops] = useState(initialStops);
  const [formError, setFormError] = useState('');
  const [saving, setSaving] = useState(false);

  const stationOptions = stations.map((s) => ({
    value: String(s.stationId),
    label: `${s.stationName} (${s.stationCode})`,
  }));

  function stationLabel(id) {
    const found = stations.find((s) => String(s.stationId) === String(id));
    return found ? `${found.stationName} (${found.stationCode})` : '';
  }

  /** Changes some fields of one row, leaves the other rows untouched. */
  function updateStop(index, changes) {
    setStops((current) => current.map((row, i) => (i === index ? { ...row, ...changes } : row)));
  }

  /** Inserts a new intermediate stop just before the destination row. */
  function addStop() {
    setStops((current) => [...current.slice(0, -1), newStopRow(), current[current.length - 1]]);
  }

  /** Only intermediate rows can be removed (source and destination always stay). */
  function removeStop(index) {
    setStops((current) => current.filter((_, i) => i !== index));
  }

  async function handleSubmit(event) {
    event.preventDefault();

    const problem = validateRoute(routeName, sourceId, destId, stops);
    setFormError(problem);
    if (problem) {
      return;
    }

    const lastIndex = stops.length - 1;
    const body = {
      routeName: routeName.trim(),
      sourceStationId: Number(sourceId),
      destStationId: Number(destId),
      stops: stops.map((stop, i) => ({
        stationId: Number(stationIdOfRow(i, stops, sourceId, destId)),
        stopSeq: i + 1,
        // First stop has no arrival, last stop has no departure.
        arrivalTime: i === 0 ? null : toApiTime(stop.arrivalTime),
        departureTime: i === lastIndex ? null : toApiTime(stop.departureTime),
        dayOffset: i === 0 ? 0 : Number(stop.dayOffset),
        distanceFromSourceKm: i === 0 ? 0 : Number(stop.distance),
      })),
    };

    setSaving(true);
    try {
      const result = await createRoute(body);
      onCreated(`Route "${body.routeName}" created (id ${result.routeId}) with ${body.stops.length} stops.`);
    } catch (err) {
      setFormError(err.message || 'Could not create the route.');
    } finally {
      setSaving(false);
    }
  }

  /** One bordered block per stop. */
  function renderStopRow(stop, index) {
    const isFirst = index === 0;
    const isLast = index === stops.length - 1;
    const role = isFirst ? 'Source' : isLast ? 'Destination' : 'Intermediate stop';

    return (
      <div key={stop.key} className="space-y-3 rounded-lg border border-gray-200 p-4">
        <div className="flex items-center justify-between">
          <span className="font-medium">
            Stop {index + 1}: {role}
          </span>
          {!isFirst && !isLast && (
            <Button variant="danger" onClick={() => removeStop(index)}>
              Remove
            </Button>
          )}
        </div>

        <div className="grid gap-3 sm:grid-cols-2 md:grid-cols-5">
          {/* Station: fixed for source and destination, chosen for intermediate stops. */}
          {isFirst || isLast ? (
            <Input
              label="Station"
              name={`station-${stop.key}`}
              value={stationLabel(isFirst ? sourceId : destId)}
              placeholder="Choose it above"
              disabled
              readOnly
            />
          ) : (
            <Select
              label="Station"
              name={`station-${stop.key}`}
              value={stop.stationId}
              onChange={(e) => updateStop(index, { stationId: e.target.value })}
              options={stationOptions}
              placeholder="Select station"
            />
          )}

          <Input
            label="Arrival"
            name={`arrival-${stop.key}`}
            type="time"
            value={isFirst ? '' : stop.arrivalTime}
            onChange={(e) => updateStop(index, { arrivalTime: e.target.value })}
            disabled={isFirst}
          />
          <Input
            label="Departure"
            name={`departure-${stop.key}`}
            type="time"
            value={isLast ? '' : stop.departureTime}
            onChange={(e) => updateStop(index, { departureTime: e.target.value })}
            disabled={isLast}
          />
          <Input
            label="Day offset (0-3)"
            name={`day-${stop.key}`}
            type="number"
            min={0}
            max={3}
            value={isFirst ? '0' : stop.dayOffset}
            onChange={(e) => updateStop(index, { dayOffset: e.target.value })}
            disabled={isFirst}
          />
          <Input
            label="Km from source"
            name={`km-${stop.key}`}
            type="number"
            min={0}
            value={isFirst ? '0' : stop.distance}
            onChange={(e) => updateStop(index, { distance: e.target.value })}
            disabled={isFirst}
          />
        </div>
      </div>
    );
  }

  return (
    <Card title="Create a route">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid gap-4 md:grid-cols-3">
          <Input
            label="Route name"
            name="routeName"
            value={routeName}
            onChange={(e) => setRouteName(e.target.value)}
            placeholder="e.g. Pune Jn - Nagpur"
            maxLength={100}
            required
          />
          <Select
            label="Source station"
            name="sourceId"
            value={sourceId}
            onChange={(e) => setSourceId(e.target.value)}
            options={stationOptions}
            placeholder="Select station"
          />
          <Select
            label="Destination station"
            name="destId"
            value={destId}
            onChange={(e) => setDestId(e.target.value)}
            options={stationOptions}
            placeholder="Select station"
          />
        </div>

        <div className="space-y-3">{stops.map(renderStopRow)}</div>

        <div>
          <Button variant="secondary" onClick={addStop}>
            Add stop
          </Button>
        </div>

        {formError && <Alert tone="error">{formError}</Alert>}

        <div className="flex gap-2">
          <Button type="submit" loading={saving}>
            Create route
          </Button>
          <Button variant="secondary" onClick={onCancel} disabled={saving}>
            Cancel
          </Button>
        </div>
      </form>
    </Card>
  );
}

// -------------------------------------------------------------------- page

/** Routes and stations are loaded together (stations are needed for names and for the form). */
async function loadPageData() {
  const [routes, stations] = await Promise.all([fetchRoutes(), fetchStations()]);
  return { routes, stations };
}

export default function AdminRoutesPage() {
  const pageState = useAsync(loadPageData, []);
  const [showForm, setShowForm] = useState(false);
  const [message, setMessage] = useState('');
  const [viewingRoute, setViewingRoute] = useState(null); // route whose stops are shown in the modal

  const routes = pageState.data ? pageState.data.routes : [];
  const stations = pageState.data ? pageState.data.stations : [];

  function stationName(id) {
    const found = stations.find((s) => s.stationId === id);
    return found ? found.stationName : `Station ${id}`;
  }

  function handleCreated(text) {
    setShowForm(false);
    setMessage(text);
    pageState.reload();
  }

  const columns = [
    { key: 'routeName', header: 'Route' },
    { key: 'sourceStationId', header: 'From', render: (row) => stationName(row.sourceStationId) },
    { key: 'destStationId', header: 'To', render: (row) => stationName(row.destStationId) },
    {
      key: 'actions',
      header: '',
      render: (row) => (
        <Button variant="secondary" onClick={() => setViewingRoute(row)}>
          View stops
        </Button>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Manage routes"
        subtitle="A route is an ordered list of stops. Trains run on a route."
        actions={
          !showForm && (
            <Button
              onClick={() => {
                setMessage('');
                setShowForm(true);
              }}
            >
              New route
            </Button>
          )
        }
      />

      {message && <Alert tone="success">{message}</Alert>}

      {pageState.error && <Alert tone="error">{pageState.error.message}</Alert>}

      {pageState.loading && !pageState.data && <Spinner />}

      {showForm && pageState.data && (
        <CreateRouteForm stations={stations} onCreated={handleCreated} onCancel={() => setShowForm(false)} />
      )}

      {pageState.data && (
        <Card title="All routes">
          <Table columns={columns} rows={routes} rowKey="routeId" emptyText="No routes yet. Create the first one." />
        </Card>
      )}

      {viewingRoute && <RouteStopsModal route={viewingRoute} onClose={() => setViewingRoute(null)} />}
    </div>
  );
}
