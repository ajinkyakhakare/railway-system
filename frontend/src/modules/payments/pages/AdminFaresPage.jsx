// Task G4.5 (Group 4: Payment, Cancellation & Refund) - page /admin/fares (ADMIN only)
//
// Three parts:
//   1. fare rules        - edit rate per km and minimum fare, Save per row (fires trg_fare_audit)
//   2. concession rules  - edit discount percent, Save per row
//   3. fare audit log    - read-only, reloaded after every successful save
import { useEffect, useState } from 'react';
import { useAsync } from '@/hooks/useAsync';
import { formatDateTime, formatMoney } from '@/utils/format';
import { Alert, Button, Card, Input, PageHeader, Spinner, Table } from '@/components/ui';
import {
  getConcessionRules,
  getErrorMessage,
  getFareAudit,
  getFareRules,
  updateConcessionRule,
  updateFareRule,
} from '../api';

// A money / percent value typed by the admin: digits with at most two decimals.
const TWO_DECIMALS = /^\d+(\.\d{1,2})?$/;

// Limits that come from the column types (DECIMAL(6,2) and DECIMAL(8,2)).
const MAX_RATE_PER_KM = 9999.99;
const MAX_MIN_FARE = 999999.99;

// Draft values are kept as strings because that is what an <input> gives us.
function fareDraftFrom(row) {
  return { baseFarePerKm: String(row.baseFarePerKm), minFare: String(row.minFare) };
}

export default function AdminFaresPage() {
  const fareRules = useAsync(() => getFareRules(), []);
  const concessionRules = useAsync(() => getConcessionRules(), []);
  const audit = useAsync(() => getFareAudit(), []);

  // Edited-but-not-saved values, keyed by rule id.
  const [fareDrafts, setFareDrafts] = useState({});
  const [concessionDrafts, setConcessionDrafts] = useState({});
  const [savingKey, setSavingKey] = useState(''); // e.g. "fare-3" or "concession-2"
  const [message, setMessage] = useState(null); // {tone: 'success'|'error', text}

  // When rules arrive (or are reloaded) create a draft only for rows that have none yet,
  // so a reload after one Save never wipes unsaved edits in other rows.
  useEffect(() => {
    if (!fareRules.data) return;
    setFareDrafts((previous) => {
      const next = { ...previous };
      fareRules.data.forEach((row) => {
        if (!next[row.fareRuleId]) next[row.fareRuleId] = fareDraftFrom(row);
      });
      return next;
    });
  }, [fareRules.data]);

  useEffect(() => {
    if (!concessionRules.data) return;
    setConcessionDrafts((previous) => {
      const next = { ...previous };
      concessionRules.data.forEach((row) => {
        if (next[row.concessionRuleId] === undefined) {
          next[row.concessionRuleId] = String(row.discountPercent);
        }
      });
      return next;
    });
  }, [concessionRules.data]);

  // Draft of a row, falling back to the saved values on the very first render.
  function getFareDraft(row) {
    return fareDrafts[row.fareRuleId] ?? fareDraftFrom(row);
  }

  function getConcessionDraft(row) {
    return concessionDrafts[row.concessionRuleId] ?? String(row.discountPercent);
  }

  function changeFareDraft(row, field, value) {
    setFareDrafts((previous) => ({
      ...previous,
      [row.fareRuleId]: { ...getFareDraft(row), [field]: value },
    }));
  }

  function changeConcessionDraft(row, value) {
    setConcessionDrafts((previous) => ({ ...previous, [row.concessionRuleId]: value }));
  }

  // "Save" is enabled only when a draft differs from the stored row.
  function isFareDirty(row) {
    const draft = getFareDraft(row);
    return (
      Number(draft.baseFarePerKm) !== Number(row.baseFarePerKm) ||
      Number(draft.minFare) !== Number(row.minFare)
    );
  }

  function isConcessionDirty(row) {
    return Number(getConcessionDraft(row)) !== Number(row.discountPercent);
  }

  async function saveFareRule(row) {
    const draft = getFareDraft(row);
    const perKm = draft.baseFarePerKm.trim();
    const minFare = draft.minFare.trim();

    if (!TWO_DECIMALS.test(perKm) || Number(perKm) <= 0 || Number(perKm) > MAX_RATE_PER_KM) {
      setMessage({
        tone: 'error',
        text: `${row.classCode}: the rate per km must be above 0 and at most ${MAX_RATE_PER_KM}, with up to two decimals.`,
      });
      return;
    }
    if (!TWO_DECIMALS.test(minFare) || Number(minFare) > MAX_MIN_FARE) {
      setMessage({
        tone: 'error',
        text: `${row.classCode}: the minimum fare must be 0 or more and at most ${MAX_MIN_FARE}, with up to two decimals.`,
      });
      return;
    }

    setMessage(null);
    setSavingKey(`fare-${row.fareRuleId}`);
    try {
      const saved = await updateFareRule(row.fareRuleId, {
        baseFarePerKm: Number(perKm),
        minFare: Number(minFare),
      });
      setFareDrafts((previous) => ({ ...previous, [row.fareRuleId]: fareDraftFrom(saved) }));
      setMessage({ tone: 'success', text: `Fare rule for ${row.classCode} saved.` });
      fareRules.reload();
      audit.reload(); // the trigger wrote a new audit row
    } catch (err) {
      setMessage({ tone: 'error', text: getErrorMessage(err) });
    } finally {
      setSavingKey('');
    }
  }

  async function saveConcessionRule(row) {
    const percent = getConcessionDraft(row).trim();

    if (!TWO_DECIMALS.test(percent) || Number(percent) > 100) {
      setMessage({
        tone: 'error',
        text: `${row.concessionType}: the discount must be between 0 and 100, with up to two decimals.`,
      });
      return;
    }

    setMessage(null);
    setSavingKey(`concession-${row.concessionRuleId}`);
    try {
      const saved = await updateConcessionRule(row.concessionRuleId, {
        discountPercent: Number(percent),
      });
      setConcessionDrafts((previous) => ({
        ...previous,
        [row.concessionRuleId]: String(saved.discountPercent),
      }));
      setMessage({ tone: 'success', text: `Concession rule ${row.concessionType} saved.` });
      concessionRules.reload();
    } catch (err) {
      setMessage({ tone: 'error', text: getErrorMessage(err) });
    } finally {
      setSavingKey('');
    }
  }

  function reloadAll() {
    setMessage(null);
    fareRules.reload();
    concessionRules.reload();
    audit.reload();
  }

  // The audit table stores only Fare_Rule_ID, so look the class code up from the loaded rules.
  function classCodeOf(fareRuleId) {
    const rule = (fareRules.data ?? []).find((row) => row.fareRuleId === fareRuleId);
    return rule ? rule.classCode : `#${fareRuleId}`;
  }

  // ------------------------------------------------------------- columns
  const fareColumns = [
    { key: 'classCode', header: 'Class' },
    {
      key: 'baseFarePerKm',
      header: 'Rate per km (INR)',
      render: (row) => (
        <Input
          name={`baseFarePerKm-${row.fareRuleId}`}
          type="number"
          step="0.01"
          min="0"
          value={getFareDraft(row).baseFarePerKm}
          onChange={(event) => changeFareDraft(row, 'baseFarePerKm', event.target.value)}
          aria-label={`Rate per km for ${row.classCode}`}
        />
      ),
    },
    {
      key: 'minFare',
      header: 'Minimum fare (INR)',
      render: (row) => (
        <Input
          name={`minFare-${row.fareRuleId}`}
          type="number"
          step="0.01"
          min="0"
          value={getFareDraft(row).minFare}
          onChange={(event) => changeFareDraft(row, 'minFare', event.target.value)}
          aria-label={`Minimum fare for ${row.classCode}`}
        />
      ),
    },
    { key: 'updatedAt', header: 'Last updated', render: (row) => formatDateTime(row.updatedAt) },
    {
      key: 'save',
      header: '',
      render: (row) => (
        <Button
          onClick={() => saveFareRule(row)}
          loading={savingKey === `fare-${row.fareRuleId}`}
          disabled={savingKey !== '' || !isFareDirty(row)}
        >
          Save
        </Button>
      ),
    },
  ];

  const concessionColumns = [
    { key: 'concessionType', header: 'Concession' },
    { key: 'description', header: 'Description', render: (row) => row.description || '-' },
    {
      key: 'discountPercent',
      header: 'Discount %',
      render: (row) => (
        <Input
          name={`discountPercent-${row.concessionRuleId}`}
          type="number"
          step="0.01"
          min="0"
          max="100"
          value={getConcessionDraft(row)}
          onChange={(event) => changeConcessionDraft(row, event.target.value)}
          aria-label={`Discount percent for ${row.concessionType}`}
        />
      ),
    },
    {
      key: 'save',
      header: '',
      render: (row) => (
        <Button
          onClick={() => saveConcessionRule(row)}
          loading={savingKey === `concession-${row.concessionRuleId}`}
          disabled={savingKey !== '' || !isConcessionDirty(row)}
        >
          Save
        </Button>
      ),
    },
  ];

  const auditColumns = [
    { key: 'changedAt', header: 'Changed at', render: (row) => formatDateTime(row.changedAt) },
    { key: 'fareRuleId', header: 'Class', render: (row) => classCodeOf(row.fareRuleId) },
    {
      key: 'baseFarePerKm',
      header: 'Rate per km',
      render: (row) => `${row.oldBaseFarePerKm} to ${row.newBaseFarePerKm}`,
    },
    {
      key: 'minFare',
      header: 'Minimum fare',
      render: (row) => `${formatMoney(row.oldMinFare)} to ${formatMoney(row.newMinFare)}`,
    },
    { key: 'changedBy', header: 'Changed by' },
  ];

  // A Card body with loading and error handling, shared by the three parts.
  function renderSection(state, table) {
    return (
      <>
        {state.error && <Alert tone="error">{getErrorMessage(state.error)}</Alert>}
        {state.loading && !state.data && (
          <div className="flex justify-center py-8">
            <Spinner />
          </div>
        )}
        {state.data && table}
      </>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Manage fares"
        subtitle="Change the fare rules and concession discounts. Every fare change is written to the audit log."
        actions={
          <Button variant="secondary" onClick={reloadAll}>
            Refresh
          </Button>
        }
      />

      {message && <Alert tone={message.tone}>{message.text}</Alert>}

      <Card title="Fare rules">
        {renderSection(
          fareRules,
          <Table
            columns={fareColumns}
            rows={fareRules.data ?? []}
            rowKey="fareRuleId"
            emptyText="No fare rules found."
          />
        )}
      </Card>

      <Card title="Concession rules">
        {renderSection(
          concessionRules,
          <Table
            columns={concessionColumns}
            rows={concessionRules.data ?? []}
            rowKey="concessionRuleId"
            emptyText="No concession rules found."
          />
        )}
      </Card>

      <Card title="Fare audit log">
        {renderSection(
          audit,
          <Table
            columns={auditColumns}
            rows={audit.data ?? []}
            rowKey="auditId"
            emptyText="No fare changes have been recorded yet."
          />
        )}
      </Card>
    </div>
  );
}
