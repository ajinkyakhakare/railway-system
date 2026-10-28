// G2.5 - My Passengers page (frontend/src/modules/users/pages/PassengersPage.jsx)
// Lists the logged-in user's saved passengers and lets them add, edit and delete.
// ageCategory (CHILD / ADULT / SENIOR) is computed by the database (fn_age_category).
import { useState } from "react";
import { useAsync } from "@/hooks/useAsync";
import {
  Alert,
  Badge,
  Button,
  Card,
  Input,
  Modal,
  PageHeader,
  Select,
  Spinner,
  Table,
} from "@/components/ui";
import { formatDate, todayISO } from "@/utils/format";
import {
  createPassenger,
  deletePassenger,
  listPassengers,
  updatePassenger,
} from "../api";

const GENDER_OPTIONS = [
  { value: "M", label: "Male" },
  { value: "F", label: "Female" },
  { value: "O", label: "Other" },
];

// Only these can be declared by the user; SENIOR and CHILD are automatic.
const CONCESSION_OPTIONS = [
  { value: "NONE", label: "None" },
  { value: "GOVT", label: "Government employee" },
  { value: "SOLDIER", label: "Soldier" },
];

const AGE_TONES = { CHILD: "blue", ADULT: "gray", SENIOR: "yellow" };

const EMPTY_FORM = {
  fullName: "",
  dateOfBirth: "",
  gender: "",
  concessionType: "NONE",
};

function genderLabel(code) {
  const match = GENDER_OPTIONS.find((option) => option.value === code);
  return match ? match.label : code;
}

function validate(form) {
  const errors = {};
  const name = form.fullName.trim();
  if (!name) errors.fullName = "Full name is required.";
  else if (name.length > 80) errors.fullName = "Full name can have at most 80 characters.";

  if (!form.dateOfBirth) errors.dateOfBirth = "Date of birth is required.";
  else if (form.dateOfBirth > todayISO()) errors.dateOfBirth = "Date of birth cannot be in the future.";

  if (!GENDER_OPTIONS.some((option) => option.value === form.gender)) {
    errors.gender = "Select a gender.";
  }
  if (!CONCESSION_OPTIONS.some((option) => option.value === form.concessionType)) {
    errors.concessionType = "Select a concession type.";
  }
  return errors;
}

export default function PassengersPage() {
  const { data, loading, error: loadError, reload } = useAsync(() => listPassengers(), []);

  const [success, setSuccess] = useState("");

  // Add / edit modal. editing = null means "add a new passenger".
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [fieldErrors, setFieldErrors] = useState({});
  const [formError, setFormError] = useState("");
  const [saving, setSaving] = useState(false);

  // Delete confirmation modal.
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleteError, setDeleteError] = useState("");
  const [deleting, setDeleting] = useState(false);

  // ----- add / edit -----

  function openAddForm() {
    setEditing(null);
    setForm(EMPTY_FORM);
    setFieldErrors({});
    setFormError("");
    setSuccess("");
    setFormOpen(true);
  }

  function openEditForm(passenger) {
    setEditing(passenger);
    setForm({
      fullName: passenger.fullName || "",
      dateOfBirth: passenger.dateOfBirth || "",
      gender: passenger.gender || "",
      concessionType: passenger.concessionType || "NONE",
    });
    setFieldErrors({});
    setFormError("");
    setSuccess("");
    setFormOpen(true);
  }

  function closeForm() {
    if (!saving) setFormOpen(false);
  }

  function handleChange(event) {
    const { name, value } = event.target;
    setForm((previous) => ({ ...previous, [name]: value }));
  }

  async function handleSave(event) {
    event.preventDefault();
    const errors = validate(form);
    setFieldErrors(errors);
    setFormError("");
    if (Object.keys(errors).length > 0) return;

    const body = {
      fullName: form.fullName.trim(),
      dateOfBirth: form.dateOfBirth,
      gender: form.gender,
      concessionType: form.concessionType,
    };

    setSaving(true);
    try {
      if (editing) {
        await updatePassenger(editing.passengerId, body);
        setSuccess(`${body.fullName} was updated.`);
      } else {
        await createPassenger(body);
        setSuccess(`${body.fullName} was added to your passengers.`);
      }
      setFormOpen(false);
      reload();
    } catch (err) {
      setFormError(err.message || "Could not save the passenger.");
    } finally {
      setSaving(false);
    }
  }

  // ----- delete -----

  function openDelete(passenger) {
    setDeleteTarget(passenger);
    setDeleteError("");
    setSuccess("");
  }

  function closeDelete() {
    if (!deleting) setDeleteTarget(null);
  }

  async function handleDelete() {
    setDeleting(true);
    setDeleteError("");
    try {
      await deletePassenger(deleteTarget.passengerId);
      setSuccess(`${deleteTarget.fullName} was deleted.`);
      setDeleteTarget(null);
      reload();
    } catch (err) {
      if (err.code === "PASSENGER_IN_USE") {
        setDeleteError(
          `${deleteTarget.fullName} is part of an existing booking, so they cannot be deleted. ` +
            "Passengers with bookings must be kept for ticket and refund records."
        );
      } else {
        setDeleteError(err.message || "Could not delete the passenger.");
      }
    } finally {
      setDeleting(false);
    }
  }

  // ----- table -----

  const columns = [
    { key: "fullName", header: "Name" },
    {
      key: "dateOfBirth",
      header: "Date of birth",
      render: (row) => formatDate(row.dateOfBirth),
    },
    { key: "gender", header: "Gender", render: (row) => genderLabel(row.gender) },
    { key: "concessionType", header: "Declared concession" },
    {
      key: "ageCategory",
      header: "Age category",
      render: (row) => <Badge tone={AGE_TONES[row.ageCategory] || "gray"}>{row.ageCategory}</Badge>,
    },
    {
      key: "actions",
      header: "Actions",
      render: (row) => (
        <div className="flex gap-2">
          <Button variant="secondary" onClick={() => openEditForm(row)}>
            Edit
          </Button>
          <Button variant="danger" onClick={() => openDelete(row)}>
            Delete
          </Button>
        </div>
      ),
    },
  ];

  const passengers = data || [];

  return (
    <div>
      <PageHeader
        title="My Passengers"
        subtitle="Save the people you travel with so you can pick them quickly while booking."
        actions={<Button onClick={openAddForm}>Add passenger</Button>}
      />

      {success && (
        <div className="mb-4">
          <Alert tone="success">{success}</Alert>
        </div>
      )}

      {loadError && (
        <div className="mb-4">
          <Alert tone="error">{loadError.message || "Could not load your passengers."}</Alert>
        </div>
      )}

      {loading && !data ? (
        <div className="flex justify-center py-12">
          <Spinner />
        </div>
      ) : (
        <Card>
          <Table
            columns={columns}
            rows={passengers}
            rowKey="passengerId"
            emptyText="You have not added any passengers yet. Use Add passenger to create one."
          />
        </Card>
      )}

      {/* Add / edit form */}
      <Modal
        open={formOpen}
        title={editing ? "Edit passenger" : "Add passenger"}
        onClose={closeForm}
      >
        <form onSubmit={handleSave} noValidate className="space-y-4">
          {formError && <Alert tone="error">{formError}</Alert>}

          <Input
            label="Full name"
            name="fullName"
            value={form.fullName}
            onChange={handleChange}
            error={fieldErrors.fullName}
            placeholder="As on the ID card"
            required
          />
          <Input
            label="Date of birth"
            name="dateOfBirth"
            type="date"
            value={form.dateOfBirth}
            onChange={handleChange}
            error={fieldErrors.dateOfBirth}
            max={todayISO()}
            required
          />
          <Select
            label="Gender"
            name="gender"
            value={form.gender}
            onChange={handleChange}
            options={GENDER_OPTIONS}
            error={fieldErrors.gender}
            placeholder="Select gender"
          />
          <Select
            label="Concession"
            name="concessionType"
            value={form.concessionType}
            onChange={handleChange}
            options={CONCESSION_OPTIONS}
            error={fieldErrors.concessionType}
          />
          <p className="text-sm text-gray-500">
            Senior citizen (60+) and child (under 12) concessions are applied automatically
            from the date of birth. Choose a concession here only if it is one of the above.
          </p>

          <div className="flex justify-end gap-3">
            <Button variant="secondary" onClick={closeForm} disabled={saving}>
              Cancel
            </Button>
            <Button type="submit" loading={saving}>
              {editing ? "Save changes" : "Add passenger"}
            </Button>
          </div>
        </form>
      </Modal>

      {/* Delete confirmation */}
      <Modal
        open={deleteTarget !== null}
        title="Delete passenger"
        onClose={closeDelete}
      >
        <div className="space-y-4">
          {deleteError && <Alert tone="error">{deleteError}</Alert>}
          <p className="text-gray-700">
            Delete <span className="font-semibold">{deleteTarget?.fullName}</span> from your
            passengers? This cannot be undone.
          </p>
          <div className="flex justify-end gap-3">
            <Button variant="secondary" onClick={closeDelete} disabled={deleting}>
              {deleteError ? "Close" : "Cancel"}
            </Button>
            {!deleteError && (
              <Button variant="danger" onClick={handleDelete} loading={deleting}>
                Delete
              </Button>
            )}
          </div>
        </div>
      </Modal>
    </div>
  );
}
