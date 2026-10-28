// Task G1.5 | Group G1 (Train, Station & Route) | Public page: searchable list of all trains.
//
// The text box filters by train name or number (query parameter "q" of GET /trains).
// Each row links to the timetable page /trains/:trainId.

import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useAsync } from '@/hooks/useAsync';
import { Alert, Badge, Button, Card, Input, PageHeader, Spinner, Table } from '@/components/ui';
import { fetchTrains } from '../api';

export default function TrainListPage() {
  // "searchText" is what the user is typing; "query" is what was actually searched.
  // The list reloads only when the user presses Search (simple and easy to explain).
  const [searchText, setSearchText] = useState('');
  const [query, setQuery] = useState('');

  const trainsState = useAsync(() => fetchTrains(query), [query]);
  const trains = trainsState.data || [];

  function handleSubmit(event) {
    event.preventDefault();
    setQuery(searchText.trim());
  }

  function handleClear() {
    setSearchText('');
    setQuery('');
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
      key: 'timetable',
      header: '',
      render: (row) => (
        <Link to={`/trains/${row.trainId}`} className="font-medium text-blue-600 hover:underline">
          View timetable
        </Link>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader title="Trains" subtitle="Browse all trains and open their timetables." />

      <Card>
        <form onSubmit={handleSubmit} className="flex flex-wrap items-end gap-3">
          <div className="min-w-[16rem] flex-1">
            <Input
              label="Train name or number"
              name="q"
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              placeholder="e.g. Deccan or 12301"
            />
          </div>
          <Button type="submit">Search</Button>
          {(query || searchText) && (
            <Button variant="secondary" onClick={handleClear}>
              Clear
            </Button>
          )}
        </form>
      </Card>

      {trainsState.error && <Alert tone="error">{trainsState.error.message}</Alert>}

      {trainsState.loading && !trainsState.data && <Spinner />}

      {trainsState.data && (
        <Card title={query ? `Results for "${query}"` : 'All trains'}>
          <Table
            columns={columns}
            rows={trains}
            rowKey="trainId"
            emptyText={query ? 'No train matches your search.' : 'No trains available yet.'}
          />
        </Card>
      )}
    </div>
  );
}
