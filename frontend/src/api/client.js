// Shared HTTP client for every module.
//
// - Base URL is /api/v1 (the Vite dev server proxies /api to the Spring Boot backend).
// - Adds "Authorization: Bearer <railway_token>" when a token is stored.
// - The backend always answers with an envelope:
//     success -> { "success": true,  "data": ... }
//     failure -> { "success": false, "error": { "code": "...", "message": "..." } }
//   The methods below return ONLY the "data" part, and throw an ApiError on failure.
import axios from 'axios';

export const TOKEN_KEY = 'railway_token';
export const USER_KEY = 'railway_user';

// 401 answers that are normal business results (wrong password / wrong OTP).
// They must NOT log the user out, so they never trigger the "session expired" redirect.
const BUSINESS_401_CODES = ['INVALID_CREDENTIALS', 'OTP_INVALID'];

/** Error thrown by every failed API call. */
export class ApiError extends Error {
  constructor(code, message, status) {
    super(message);
    this.name = 'ApiError';
    this.code = code; // e.g. "SEAT_UNAVAILABLE" (see contract C7)
    this.message = message; // readable text that can be shown to the user
    this.status = status; // HTTP status, 0 when the server could not be reached
  }
}

// AuthContext registers a function here so a 401 can clear React state and use the router.
let unauthorizedHandler = null;

export function setUnauthorizedHandler(handler) {
  unauthorizedHandler = handler;
}

function handleSessionExpired() {
  if (unauthorizedHandler) {
    unauthorizedHandler();
    return;
  }
  // Fallback when no AuthProvider is mounted: clear the storage and do a full page load.
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
  window.location.assign('/login');
}

const http = axios.create({
  baseURL: '/api/v1',
  headers: { 'Content-Type': 'application/json' },
});

// Attach the JWT to every request.
http.interceptors.request.use((config) => {
  const token = localStorage.getItem(TOKEN_KEY);
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Remove undefined / null / empty-string query parameters so "?q=" is never sent by accident.
function cleanParams(params) {
  if (!params) return params;
  const cleaned = {};
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') {
      cleaned[key] = value;
    }
  });
  return cleaned;
}

// Turn any axios failure into an ApiError.
function toApiError(axiosError) {
  const response = axiosError.response;

  // No response at all: backend down, CORS problem or network failure.
  if (!response) {
    return new ApiError('NETWORK_ERROR', 'Cannot reach the server. Please check your connection and try again.', 0);
  }

  const body = response.data;
  if (body && body.error && body.error.code) {
    return new ApiError(body.error.code, body.error.message || 'Request failed', response.status);
  }
  // The response was not our envelope (for example a proxy error page).
  return new ApiError('INTERNAL_ERROR', 'Unexpected server response (HTTP ' + response.status + ')', response.status);
}

// Send the request, unwrap the envelope, and convert failures to ApiError.
async function send(config) {
  let response;
  try {
    response = await http.request({ ...config, params: cleanParams(config.params) });
  } catch (axiosError) {
    const apiError = toApiError(axiosError);
    if (apiError.status === 401 && !BUSINESS_401_CODES.includes(apiError.code)) {
      handleSessionExpired();
    }
    throw apiError;
  }

  const body = response.data;
  if (body && typeof body === 'object' && typeof body.success === 'boolean') {
    if (!body.success) {
      const err = body.error || {};
      throw new ApiError(err.code || 'INTERNAL_ERROR', err.message || 'Request failed', response.status);
    }
    return body.data;
  }
  // Endpoints that do not use the envelope (or an empty body) are returned as they are.
  return body === '' ? null : body;
}

const client = {
  get: (url, config = {}) => send({ ...config, method: 'get', url }),
  post: (url, body, config = {}) => send({ ...config, method: 'post', url, data: body }),
  put: (url, body, config = {}) => send({ ...config, method: 'put', url, data: body }),
  delete: (url, config = {}) => send({ ...config, method: 'delete', url }),
};

export default client;
