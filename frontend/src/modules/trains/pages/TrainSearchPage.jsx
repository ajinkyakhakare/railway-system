// Task G1.5 | Group G1 (Train, Station & Route) | Public page: search trains between two stations on a date.
//
// Flow: choose From / To / date -> "Search trains" -> results table ->
// "Check availability" opens /availability/<runId>?from=<fromStationId>&to=<toStationId> (booking module).

import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAsync } from '@/hooks/useAsync';
import { Alert, Badge, Button, Card, Input, PageHeader, Select, Spinner, Table } from '@/components/ui';
import { formatDate, formatTime, todayISO } from '@/utils/format';
import { fetchStations, searchTrains } from '../api';

/** 250 minutes -> "4h 10m". Returns a dash when the value is missing. */
function formatDuration(totalMinutes) {
  if (totalMinutes === null || totalMinutes === undefined) {
    return '—';
  }
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${hours}h ${String(minutes).padStart(2, '0')}m`;
}

/** Shows "06:00" or a dash when the time is missing. */
function showTime(value) {
  return value ? formatTime(value) : '—';
}

export default function TrainSearchPage() {
  const navigate = useNavigate();

  // Stations for the two drop-downs.
  const stationsState = useAsync(() => fetchStations(), []);
  const stations = stationsState.data || [];

  // Form fields. Select values are strings; they are converted to numbers when searching.
  const [fromStationId, setFromStationId] = useState('');
  const [toStationId, setToStationId] = useState('');
  const [date, setDate] = useState(todayISO());

  // Search state.
  const [searching, setSearching] = useState(false);
  const [formError, setFormError] = useState('');     // validation problem (nothing sent to server)
  const [searchError, setSearchError] = useState(''); // error returned by the server
  const [results, setResults] = useState(null);       // null = nothing searched yet
  const [searchedFor, setSearchedFor] = useState(null); // text shown above the results

  const stationOptions = stations.map((s) => ({
    value: String(s.stationId),
    label: `${s.stationName} (${s.stationCode})`,
  }));

  function stationName(id) {
    const found = stations.find((s) => String(s.stationId) === String(id));
    return found ? found.stationName : '';
  }

  /** Returns an error message, or '' when the form is valid. */
  function validateForm() {
    if (!fromStationId || !toStationId) {
      return 'Select both the From and To stations.';
    }
    if (fromStationId === toStationId) {
      return 'From and To stations must be different.';
    }
    if (!date) {
      return 'Select the journey date.';
    }
    return '';
  }

  function swapStations() {
    setFromStationId(toStationId);
    setToStationId(fromStationId);
  }

  async function handleSearch(event) {
    event.preventDefault();
    setSearchError('');

    const problem = validateForm();
    setFormError(problem);
    if (problem) {
      return;
    }

    setSearching(true);
    try {
      const rows = await searchTrains({
        fromStationId: Number(fromStationId),
        toStationId: Number(toStationId),
        date,
      });
      setResults(rows);
      setSearchedFor({
        from: stationName(fromStationId),
        to: stationName(toStationId),
        date,
      });
    } catch (err) {
      setResults(null);
      setSearchError(err.message || 'Search failed. Please try again.');
    } finally {
      setSearching(false);
    }
  }

  /** Go to the availability page of the booking module for the chosen run. */
  function checkAvailability(row) {
    navigate(`/availability/${row.runId}?from=${row.fromStationId}&to=${row.toStationId}`);
  }

  const columns = [
    { key: 'trainNo', header: 'Train no' },
    { key: 'trainName', header: 'Name' },
    { key: 'trainType', header: 'Type', render: (row) => <Badge tone="blue">{row.trainType}</Badge> },
    { key: 'departureTime', header: 'Departure', render: (row) => showTime(row.departureTime) },
    { key: 'arrivalTime', header: 'Arrival', render: (row) => showTime(row.arrivalTime) },
    { key: 'durationMin', header: 'Duration', render: (row) => formatDuration(row.durationMin) },
    { key: 'distanceKm', header: 'Distance', render: (row) => `${row.distanceKm} km` },
    {
      key: 'actions',
      header: '',
      render: (row) => (
        <Button variant="secondary" onClick={() => checkAvailability(row)}>
          Check availability
        </Button>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader title="Search trains" subtitle="Find trains between two stations on a date." />

      <Card>
        {stationsState.loading && !stationsState.data && <Spinner />}

        {stationsState.error && (
          <Alert tone="error">Could not load stations: {stationsState.error.message}</Alert>
        )}

        {!stationsState.loading && !stationsState.error && (
          <form onSubmit={handleSearch} className="space-y-4">
            <div className="grid gap-4 md:grid-cols-4">
              <Select
                label="From"
                name="fromStationId"
                value={fromStationId}
                onChange={(e) => setFromStationId(e.target.value)}
                options={stationOptions}
                placeholder="Select station"
              />
              <Select
                label="To"
                name="toStationId"
                value={toStationId}
                onChange={(e) => setToStationId(e.target.value)}
                options={stationOptions}
                placeholder="Select station"
              />
              <Input
                label="Journey date"
                name="date"
                type="date"
                value={date}
                min={todayISO()}
                onChange={(e) => setDate(e.target.value)}
              />
              <div className="flex items-end gap-2">
                <Button type="submit" loading={searching}>
                  Search trains
                </Button>
                <Button variant="secondary" onClick={swapStations} disabled={searching}>
                  Swap
                </Button>
              </div>
            </div>

            {formError && <Alert tone="error">{formError}</Alert>}
          </form>
        )}
      </Card>

      {searchError && <Alert tone="error">{searchError}</Alert>}

      {searching && <Spinner />}

      {/* No trains found. */}
      {!searching && results && results.length === 0 && (
        <Alert tone="info">
          No trains run from {searchedFor.from} to {searchedFor.to} on {formatDate(searchedFor.date)}.
          Try another date or a different pair of stations.
        </Alert>
      )}

      {/* Results table. */}
      {!searching && results && results.length > 0 && (
        <Card
          title={`${results.length} train${results.length === 1 ? '' : 's'} from ${searchedFor.from} to ${searchedFor.to} on ${formatDate(searchedFor.date)}`}
        >
          <Table columns={columns} rows={results} rowKey="runId" emptyText="No trains found." />
        </Card>
      )}
    </div>
  );
}
