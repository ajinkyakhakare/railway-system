// G2.5 - Users module API functions (frontend/src/modules/users/api.js)
// Every function wraps the shared axios client (C10). The client already
// prefixes "/api/v1" and returns the UNWRAPPED ApiResponse.data, so each
// function simply resolves to the payload described in contract C9 (G2).
import client from "@/api/client";

// ---------- Authentication ----------

// POST /auth/register  {email, password, fullName, phone} -> {userId}
export function registerUser(body) {
  return client.post("/auth/register", body);
}

// POST /auth/login  {email, password}
// -> {token|null, otpRequired, challengeId|null, devOtp|null, user|null}
export function loginUser(body) {
  return client.post("/auth/login", body);
}

// POST /auth/verify-otp  {challengeId, otp} -> {token, user}
export function verifyLoginOtp(body) {
  return client.post("/auth/verify-otp", body);
}

// POST /auth/payment-otp  {} -> {challengeId, expiresAt, devOtp|null}
// (kept here because it is a G2 endpoint; the payments module may reuse it)
export function requestPaymentOtp() {
  return client.post("/auth/payment-otp", {});
}

// ---------- Own profile ----------

// GET /users/me -> {userId, email, fullName, phone, roles[]}
export function getMyProfile() {
  return client.get("/users/me");
}

// PUT /users/me  {fullName, phone} -> same shape as GET /users/me
export function updateMyProfile(body) {
  return client.put("/users/me", body);
}

// ---------- Own passengers ----------

// GET /passengers -> [{passengerId, fullName, dateOfBirth, gender,
//                      concessionType, ageCategory}]
export function listPassengers() {
  return client.get("/passengers");
}

// POST /passengers  {fullName, dateOfBirth, gender, concessionType}
export function createPassenger(body) {
  return client.post("/passengers", body);
}

// PUT /passengers/{id}  same body as create -> passenger object
export function updatePassenger(passengerId, body) {
  return client.put(`/passengers/${passengerId}`, body);
}

// DELETE /passengers/{id} -> {deleted: true}
// Fails with PASSENGER_IN_USE when the passenger is on a booking.
export function deletePassenger(passengerId) {
  return client.delete(`/passengers/${passengerId}`);
}

// ---------- Admin: user management ----------

// GET /admin/users -> rows of view v_user_account
// (roles arrives as one comma separated string, e.g. "ADMIN,PASSENGER")
export function listUsers() {
  return client.get("/admin/users");
}

// PUT /admin/users/{id}/roles  {roles: ["ADMIN"]} -> {userId, roles[]}
export function updateUserRoles(userId, roles) {
  return client.put(`/admin/users/${userId}/roles`, { roles });
}

// PUT /admin/users/{id}/active  {active: boolean} -> {userId, active}
export function setUserActive(userId, active) {
  return client.put(`/admin/users/${userId}/active`, { active });
}
