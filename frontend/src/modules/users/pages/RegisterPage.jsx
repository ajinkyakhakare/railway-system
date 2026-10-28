// G2.5 - Registration page (frontend/src/modules/users/pages/RegisterPage.jsx)
// POST /auth/register {email, password, fullName, phone}. The client-side rules
// mirror the database / server rules: phone = exactly 10 digits, password >= 8 chars.
import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Alert, Button, Card, Input, PageHeader } from "@/components/ui";
import { registerUser } from "../api";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_PATTERN = /^[0-9]{10}$/;

const EMPTY_FORM = {
  fullName: "",
  email: "",
  phone: "",
  password: "",
  confirmPassword: "",
};

// Returns an object {fieldName: message}; empty object means the form is valid.
function validate(form) {
  const errors = {};
  const name = form.fullName.trim();
  const email = form.email.trim();

  if (!name) errors.fullName = "Full name is required.";
  else if (name.length > 80) errors.fullName = "Full name can have at most 80 characters.";

  if (!email) errors.email = "Email is required.";
  else if (email.length > 120) errors.email = "Email can have at most 120 characters.";
  else if (!EMAIL_PATTERN.test(email)) errors.email = "Enter a valid email address.";

  if (!PHONE_PATTERN.test(form.phone)) errors.phone = "Phone must be exactly 10 digits.";

  if (form.password.length < 8) errors.password = "Password must have at least 8 characters.";

  if (!form.confirmPassword) errors.confirmPassword = "Please confirm your password.";
  else if (form.confirmPassword !== form.password) {
    errors.confirmPassword = "Passwords do not match.";
  }
  return errors;
}

export default function RegisterPage() {
  const navigate = useNavigate();
  const [form, setForm] = useState(EMPTY_FORM);
  const [fieldErrors, setFieldErrors] = useState({});
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  function handleChange(event) {
    const { name, value } = event.target;
    // Phone accepts digits only, so letters never reach the validator.
    const cleaned = name === "phone" ? value.replace(/\D/g, "").slice(0, 10) : value;
    setForm((previous) => ({ ...previous, [name]: cleaned }));
  }

  async function handleSubmit(event) {
    event.preventDefault();
    const errors = validate(form);
    setFieldErrors(errors);
    setError("");
    if (Object.keys(errors).length > 0) return;

    setLoading(true);
    try {
      await registerUser({
        email: form.email.trim(),
        password: form.password,
        fullName: form.fullName.trim(),
        phone: form.phone,
      });
      navigate("/login", {
        state: { message: "Account created successfully. Please sign in." },
      });
    } catch (err) {
      if (err.code === "EMAIL_EXISTS") {
        setFieldErrors({ email: "This email is already registered." });
      }
      setError(err.message || "Registration failed. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="mx-auto max-w-md">
      <PageHeader
        title="Create account"
        subtitle="Register once, then book tickets for yourself and your family."
      />

      <Card title="Your details">
        {error && (
          <div className="mb-4">
            <Alert tone="error">{error}</Alert>
          </div>
        )}

        <form onSubmit={handleSubmit} noValidate className="space-y-4">
          <Input
            label="Full name"
            name="fullName"
            value={form.fullName}
            onChange={handleChange}
            error={fieldErrors.fullName}
            placeholder="As on your ID card"
            autoComplete="name"
            required
          />
          <Input
            label="Email"
            name="email"
            type="email"
            value={form.email}
            onChange={handleChange}
            error={fieldErrors.email}
            placeholder="you@example.com"
            autoComplete="email"
            required
          />
          <Input
            label="Phone (10 digits)"
            name="phone"
            type="tel"
            value={form.phone}
            onChange={handleChange}
            error={fieldErrors.phone}
            placeholder="9876543210"
            autoComplete="tel"
            inputMode="numeric"
            required
          />
          <Input
            label="Password (min 8 characters)"
            name="password"
            type="password"
            value={form.password}
            onChange={handleChange}
            error={fieldErrors.password}
            autoComplete="new-password"
            required
          />
          <Input
            label="Confirm password"
            name="confirmPassword"
            type="password"
            value={form.confirmPassword}
            onChange={handleChange}
            error={fieldErrors.confirmPassword}
            autoComplete="new-password"
            required
          />
          <Button type="submit" loading={loading} className="w-full">
            Create account
          </Button>
        </form>

        <p className="mt-4 text-sm text-gray-600">
          Already registered?{" "}
          <Link to="/login" className="font-medium text-blue-700 hover:underline">
            Sign in
          </Link>
        </p>
      </Card>
    </div>
  );
}
