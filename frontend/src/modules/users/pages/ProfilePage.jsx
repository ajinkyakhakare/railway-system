// G2.5 - Profile page (frontend/src/modules/users/pages/ProfilePage.jsx)
// GET /users/me shows the account; PUT /users/me edits fullName and phone.
// Email and roles are read-only (roles are changed only by an admin).
import { useEffect, useState } from "react";
import { useAuth } from "@/auth/AuthContext";
import { useAsync } from "@/hooks/useAsync";
import {
  Alert,
  Badge,
  Button,
  Card,
  Input,
  PageHeader,
  Spinner,
} from "@/components/ui";
import { getMyProfile, updateMyProfile } from "../api";

const PHONE_PATTERN = /^[0-9]{10}$/;

// Badge colour per role name.
const ROLE_TONES = { ADMIN: "red", OPERATOR: "yellow", PASSENGER: "blue" };

function validate(form) {
  const errors = {};
  const name = form.fullName.trim();
  if (!name) errors.fullName = "Full name is required.";
  else if (name.length > 80) errors.fullName = "Full name can have at most 80 characters.";
  if (!PHONE_PATTERN.test(form.phone)) errors.phone = "Phone must be exactly 10 digits.";
  return errors;
}

export default function ProfilePage() {
  const { token, login } = useAuth();
  const { data: profile, loading, error: loadError } = useAsync(() => getMyProfile(), []);

  const [form, setForm] = useState({ fullName: "", phone: "" });
  const [fieldErrors, setFieldErrors] = useState({});
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState("");
  const [success, setSuccess] = useState("");

  // Fill the form once the profile has been loaded.
  useEffect(() => {
    if (profile) {
      setForm({ fullName: profile.fullName || "", phone: profile.phone || "" });
    }
  }, [profile]);

  function handleChange(event) {
    const { name, value } = event.target;
    const cleaned = name === "phone" ? value.replace(/\D/g, "").slice(0, 10) : value;
    setForm((previous) => ({ ...previous, [name]: cleaned }));
    setSuccess("");
  }

  async function handleSubmit(event) {
    event.preventDefault();
    const errors = validate(form);
    setFieldErrors(errors);
    setSaveError("");
    setSuccess("");
    if (Object.keys(errors).length > 0) return;

    setSaving(true);
    try {
      const updated = await updateMyProfile({
        fullName: form.fullName.trim(),
        phone: form.phone,
      });
      setForm({ fullName: updated.fullName, phone: updated.phone });
      // Keep the session user (shown in the navigation bar) in step with the new name.
      login(token, {
        userId: updated.userId,
        email: updated.email,
        fullName: updated.fullName,
        roles: updated.roles,
      });
      setSuccess("Profile updated successfully.");
    } catch (err) {
      setSaveError(err.message || "Could not update your profile.");
    } finally {
      setSaving(false);
    }
  }

  if (loading && !profile) {
    return (
      <div className="flex justify-center py-12">
        <Spinner />
      </div>
    );
  }

  if (loadError && !profile) {
    return (
      <div>
        <PageHeader title="My Profile" />
        <Alert tone="error">{loadError.message || "Could not load your profile."}</Alert>
      </div>
    );
  }

  const roles = profile?.roles || [];

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader
        title="My Profile"
        subtitle="Your account details and contact information."
      />

      <Card title="Account">
        <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <dt className="text-sm text-gray-500">Email</dt>
            <dd className="font-medium text-gray-900">{profile?.email}</dd>
          </div>
          <div>
            <dt className="text-sm text-gray-500">Roles</dt>
            <dd className="mt-1 flex flex-wrap gap-2">
              {roles.length === 0 && <span className="text-gray-500">No roles</span>}
              {roles.map((role) => (
                <Badge key={role} tone={ROLE_TONES[role] || "gray"}>
                  {role}
                </Badge>
              ))}
            </dd>
          </div>
        </dl>
      </Card>

      <Card title="Edit details">
        {success && (
          <div className="mb-4">
            <Alert tone="success">{success}</Alert>
          </div>
        )}
        {saveError && (
          <div className="mb-4">
            <Alert tone="error">{saveError}</Alert>
          </div>
        )}

        <form onSubmit={handleSubmit} noValidate className="space-y-4">
          <Input
            label="Full name"
            name="fullName"
            value={form.fullName}
            onChange={handleChange}
            error={fieldErrors.fullName}
            autoComplete="name"
            required
          />
          <Input
            label="Phone (10 digits)"
            name="phone"
            type="tel"
            value={form.phone}
            onChange={handleChange}
            error={fieldErrors.phone}
            autoComplete="tel"
            inputMode="numeric"
            required
          />
          <Button type="submit" loading={saving}>
            Save changes
          </Button>
        </form>
      </Card>
    </div>
  );
}
