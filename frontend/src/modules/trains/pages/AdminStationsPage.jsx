// Task G1.5 | Group G1 (Train, Station & Route) | Admin page: station CRUD (/admin/stations, role ADMIN).
//
// Table of stations with Edit / Delete buttons. "New station" and "Edit" open the same modal form;
// "Delete" asks for confirmation first. A station that is still used by a route cannot be deleted:
// the server refuses and its message is shown in the dialog.

import { useState } from 'react';
import { useAsync } from '@/hooks/useAsync';
import { Alert, Button, Card, Input, Modal, PageHeader, Spinner, Table } from '@/components/ui';
import { createStation, deleteStation, fetchStations, updateStation } from '../api';

// -------------------------------------------------------- create / edit form

/** station = null creates a new station, otherwise the given station is edited. */
function StationFormModal({ station, onClose, onSaved }) {
  const isEdit = station !== null;

  const [stationCode, setStationCode] = useState(station ? station.stationCode : '');
  const [stationName, setStationName] = useState(station ? station.stationName : '');
  const [city, setCity] = useState(station ? station.city : '');
  const [state, setState] = useState(station ? station.state : '');
  const [errors, setErrors] = useState({});
  const [serverError, setServerError] = useState('');
  const [saving, setSaving] = useState(false);

  /** One message per invalid field. Limits match the column sizes of table station. */
  function validate() {
    const found = {};
    const code = stationCode.trim();
    if (!code) {
      found.stationCode = 'Station code is required.';
    } else if (code.length > 5) {
      found.stationCode = 'Station code can have at most 5 characters.';
    }
    if (!stationName.trim()) {
      found.stationName = 'Station name is required.';
    } else if (stationName.trim().length > 80) {
      found.stationName = 'Station name can have at most 80 characters.';
    }
    if (!city.trim()) {
      found.city = 'City is required.';
    } else if (city.trim().length > 60) {
      found.city = 'City can have at most 60 characters.';
    }
    if (!state.trim()) {
      found.state = 'State is required.';
    } else if (state.trim().length > 60) {
      found.state = 'State can have at most 60 characters.';
    }
    return found;
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setServerError('');

    const found = validate();
    setErrors(found);
    if (Object.keys(found).length > 0) {
      return;
    }

    // Station codes are written in capitals (PUNE, CSMT, ...).
    const body = {
      stationCode: stationCode.trim().toUpperCase(),
      stationName: stationName.trim(),
      city: city.trim(),
      state: state.trim(),
    };

    setSaving(true);
    try {
      if (isEdit) {
        await updateStation(station.stationId, body);
        onSaved(`Station ${body.stationCode} updated.`);
      } else {
        await createStation(body);
        onSaved(`Station ${body.stationCode} created.`);
      }
      onClose();
    } catch (err) {
      setServerError(err.message || 'Could not save the station.');
      setSaving(false);
    }
  }

  return (
    <Modal open title={isEdit ? 'Edit station' : 'New station'} onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input
          label="Station code"
          name="stationCode"
          value={stationCode}
          onChange={(e) => setStationCode(e.target.value)}
          error={errors.stationCode}
          placeholder="e.g. PUNE"
          maxLength={5}
          required
        />
        <Input
          label="Station name"
          name="stationName"
          value={stationName}
          onChange={(e) => setStationName(e.target.value)}
          error={errors.stationName}
          placeholder="e.g. Pune Junction"
          required
        />
        <Input
          label="City"
          name="city"
          value={city}
          onChange={(e) => setCity(e.target.value)}
          error={errors.city}
          required
        />
        <Input
          label="State"
          name="state"
          value={state}
          onChange={(e) => setState(e.target.value)}
          error={errors.state}
          required
        />

        {serverError && <Alert tone="error">{serverError}</Alert>}

        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            {isEdit ? 'Save changes' : 'Create station'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}

// ------------------------------------------------------- delete confirmation

function DeleteStationModal({ station, onClose, onDeleted }) {
  const [error, setError] = useState('');
  const [deleting, setDeleting] = useState(false);

  async function handleDelete() {
    setError('');
    setDeleting(true);
    try {
      await deleteStation(station.stationId);
      onDeleted(`Station ${station.stationCode} deleted.`);
      onClose();
    } catch (err) {
      // Typical reason: the station is still used by a route or a booking.
      setError(err.message || 'Could not delete the station.');
      setDeleting(false);
    }
  }

  return (
    <Modal open title="Delete station" onClose={onClose}>
      <div className="space-y-4">
        <p>
          Delete <strong>{station.stationName}</strong> ({station.stationCode})? This cannot be undone.
          Stations that are part of a route cannot be deleted.
        </p>

        {error && <Alert tone="error">{error}</Alert>}

        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={deleting}>
            Cancel
          </Button>
          <Button variant="danger" onClick={handleDelete} loading={deleting}>
            Delete station
          </Button>
        </div>
      </div>
    </Modal>
  );
}

// -------------------------------------------------------------------- page

export default function AdminStationsPage() {
  const stationsState = useAsync(() => fetchStations(), []);
  const [message, setMessage] = useState(null); // success text shown at the top
  const [modal, setModal] = useState(null);     // {type: 'form' | 'delete', station}

  const stations = stationsState.data || [];

  /** Called by the modals after a successful change: show the message and refresh the table. */
  function handleChanged(text) {
    setMessage(text);
    stationsState.reload();
  }

  const columns = [
    { key: 'stationCode', header: 'Code' },
    { key: 'stationName', header: 'Station' },
    { key: 'city', header: 'City' },
    { key: 'state', header: 'State' },
    {
      key: 'actions',
      header: 'Actions',
      render: (row) => (
        <div className="flex gap-2">
          <Button variant="secondary" onClick={() => setModal({ type: 'form', station: row })}>
            Edit
          </Button>
          <Button variant="danger" onClick={() => setModal({ type: 'delete', station: row })}>
            Delete
          </Button>
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Manage stations"
        subtitle="Stations are used by routes, searches and bookings."
        actions={
          <Button
            onClick={() => {
              setMessage(null);
              setModal({ type: 'form', station: null });
            }}
          >
            New station
          </Button>
        }
      />

      {message && <Alert tone="success">{message}</Alert>}

      {stationsState.error && <Alert tone="error">{stationsState.error.message}</Alert>}

      {stationsState.loading && !stationsState.data && <Spinner />}

      {stationsState.data && (
        <Card title={`${stations.length} station${stations.length === 1 ? '' : 's'}`}>
          <Table columns={columns} rows={stations} rowKey="stationId" emptyText="No stations yet." />
        </Card>
      )}

      {modal && modal.type === 'form' && (
        <StationFormModal station={modal.station} onClose={() => setModal(null)} onSaved={handleChanged} />
      )}

      {modal && modal.type === 'delete' && (
        <DeleteStationModal station={modal.station} onClose={() => setModal(null)} onDeleted={handleChanged} />
      )}
    </div>
  );
}
