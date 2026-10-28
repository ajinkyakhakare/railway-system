// G2.5 - Login page (frontend/src/modules/users/pages/LoginPage.jsx)
// Step 1: email + password  ->  POST /auth/login
// Step 2 (only when the server answers otpRequired=true): OTP -> POST /auth/verify-otp
// On success the token and user go into AuthContext through useAuth().login().
import { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "@/auth/AuthContext";
import { Alert, Button, Card, Input, PageHeader } from "@/components/ui";
import { loginUser, verifyLoginOtp } from "../api";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Work out where to send the user after login. ProtectedRoute-style code may
// store location.state.from as a string or as a location object.
function getRedirectTarget(location) {
  const from = location.state?.from;
  let target = "/";
  if (typeof from === "string") {
    target = from;
  } else if (from && from.pathname) {
    target = `${from.pathname}${from.search || ""}${from.hash || ""}`;
  }
  // Never bounce back to the login / register screens.
  if (target.startsWith("/login") || target.startsWith("/register")) {
    return "/";
  }
  return target;
}

export default function LoginPage() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const [step, setStep] = useState("credentials"); // "credentials" | "otp"
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [otp, setOtp] = useState("");
  const [challengeId, setChallengeId] = useState(null);
  const [devOtp, setDevOtp] = useState(null);
  const [fieldErrors, setFieldErrors] = useState({});
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  // Message passed by RegisterPage after a successful sign-up.
  const infoMessage = location.state?.message || "";

  // Save the session and leave the login page.
  function finishLogin(token, user) {
    login(token, user);
    navigate(getRedirectTarget(location), { replace: true });
  }

  function validateCredentials() {
    const errors = {};
    if (!email.trim()) {
      errors.email = "Email is required.";
    } else if (!EMAIL_PATTERN.test(email.trim())) {
      errors.email = "Enter a valid email address.";
    }
    if (!password) {
      errors.password = "Password is required.";
    }
    return errors;
  }

  async function handleCredentialsSubmit(event) {
    event.preventDefault();
    const errors = validateCredentials();
    setFieldErrors(errors);
    setError("");
    if (Object.keys(errors).length > 0) return;

    setLoading(true);
    try {
      const result = await loginUser({ email: email.trim(), password });
      if (result.otpRequired) {
        // Second factor needed: remember the challenge and show the OTP step.
        setChallengeId(result.challengeId);
        setDevOtp(result.devOtp || null);
        setOtp("");
        setStep("otp");
      } else {
        finishLogin(result.token, result.user);
      }
    } catch (err) {
      setError(err.message || "Login failed. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  async function handleOtpSubmit(event) {
    event.preventDefault();
    setError("");
    if (!otp.trim()) {
      setFieldErrors({ otp: "Enter the one-time password." });
      return;
    }
    setFieldErrors({});

    setLoading(true);
    try {
      const result = await verifyLoginOtp({
        challengeId: Number(challengeId),
        otp: otp.trim(),
      });
      finishLogin(result.token, result.user);
    } catch (err) {
      setError(err.message || "OTP verification failed. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  // Go back from the OTP step to the email / password step.
  function handleBackToCredentials() {
    setStep("credentials");
    setOtp("");
    setChallengeId(null);
    setDevOtp(null);
    setFieldErrors({});
    setError("");
  }

  return (
    <div className="mx-auto max-w-md">
      <PageHeader
        title="Sign in"
        subtitle="Log in to book tickets and manage your passengers."
      />

      <Card title={step === "credentials" ? "Account login" : "Verify your login"}>
        {error && (
          <div className="mb-4">
            <Alert tone="error">{error}</Alert>
          </div>
        )}

        {step === "credentials" && (
          <>
            {infoMessage && !error && (
              <div className="mb-4">
                <Alert tone="success">{infoMessage}</Alert>
              </div>
            )}

            <form onSubmit={handleCredentialsSubmit} noValidate className="space-y-4">
              <Input
                label="Email"
                name="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                error={fieldErrors.email}
                placeholder="you@example.com"
                autoComplete="email"
                required
              />
              <Input
                label="Password"
                name="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                error={fieldErrors.password}
                placeholder="Your password"
                autoComplete="current-password"
                required
              />
              <Button type="submit" loading={loading} className="w-full">
                Sign in
              </Button>
            </form>

            <div className="mt-4 space-y-2 text-sm text-gray-600">
              <p>
                New here?{" "}
                <Link to="/register" className="font-medium text-blue-700 hover:underline">
                  Create an account
                </Link>
              </p>
              <Alert tone="info">
                Demo login: admin@railway.test / Test@1234
              </Alert>
            </div>
          </>
        )}

        {step === "otp" && (
          <form onSubmit={handleOtpSubmit} noValidate className="space-y-4">
            <p className="text-sm text-gray-600">
              Enter the one-time password for {email.trim()}. It is valid for 5 minutes.
            </p>
            {devOtp && (
              <Alert tone="info">Development mode: your OTP is {devOtp}</Alert>
            )}
            <Input
              label="One-time password"
              name="otp"
              value={otp}
              onChange={(e) => setOtp(e.target.value)}
              error={fieldErrors.otp}
              placeholder="Enter OTP"
              autoComplete="one-time-code"
              inputMode="numeric"
              required
            />
            <div className="flex gap-3">
              <Button type="submit" loading={loading}>
                Verify and sign in
              </Button>
              <Button variant="secondary" onClick={handleBackToCredentials} disabled={loading}>
                Back
              </Button>
            </div>
          </form>
        )}
      </Card>
    </div>
  );
}
