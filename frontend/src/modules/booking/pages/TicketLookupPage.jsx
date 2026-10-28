// G3.5 - TicketLookupPage  (route: /tickets, public)
// The visitor types a 10-digit PNR and is sent to /tickets/:pnr, which shows the status.
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button, Card, Input, PageHeader } from '@/components/ui';

// A PNR is exactly 10 digits (see fn_generate_pnr).
const PNR_PATTERN = /^[0-9]{10}$/;

export default function TicketLookupPage() {
  const navigate = useNavigate();
  const [pnr, setPnr] = useState('');
  const [error, setError] = useState('');

  // Keep only digits while typing and stop at 10 characters.
  function handleChange(event) {
    const digits = event.target.value.replace(/[^0-9]/g, '').slice(0, 10);
    setPnr(digits);
    if (error) setError('');
  }

  function handleSubmit(event) {
    event.preventDefault();
    if (!PNR_PATTERN.test(pnr)) {
      setError('Enter the 10-digit PNR printed on your ticket.');
      return;
    }
    navigate(`/tickets/${pnr}`);
  }

  return (
    <div className="mx-auto max-w-md space-y-4">
      <PageHeader title="PNR status" subtitle="Check the status of a ticket without logging in" />
      <Card>
        <form onSubmit={handleSubmit} className="space-y-4" noValidate>
          <Input
            label="PNR number"
            name="pnr"
            value={pnr}
            onChange={handleChange}
            error={error}
            placeholder="10-digit PNR"
            inputMode="numeric"
            autoComplete="off"
            required
          />
          <Button type="submit">Check status</Button>
        </form>
      </Card>
    </div>
  );
}
