// Holds the logged-in user and JWT for the whole app.
// The token and user are mirrored in localStorage (keys railway_token / railway_user)
// so a page refresh keeps the user logged in.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { TOKEN_KEY, USER_KEY, setUnauthorizedHandler } from '@/api/client';

const AuthContext = createContext(null);

// Read the saved user; a corrupted value is treated as "not logged in".
function readStoredUser() {
  try {
    const raw = localStorage.getItem(USER_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function clearStorage() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}

export function AuthProvider({ children }) {
  const navigate = useNavigate();
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY));
  const [user, setUser] = useState(readStoredUser);

  // useNavigate is not stable across route changes, so keep the latest one in a ref.
  const navigateRef = useRef(navigate);
  navigateRef.current = navigate;

  const login = useCallback((newToken, newUser) => {
    const safeUser = { ...newUser, roles: Array.isArray(newUser?.roles) ? newUser.roles : [] };
    localStorage.setItem(TOKEN_KEY, newToken);
    localStorage.setItem(USER_KEY, JSON.stringify(safeUser));
    setToken(newToken);
    setUser(safeUser);
  }, []);

  const logout = useCallback(() => {
    clearStorage();
    setToken(null);
    setUser(null);
  }, []);

  // When the API client sees an expired session (HTTP 401) it calls this function.
  useEffect(() => {
    setUnauthorizedHandler(() => {
      clearStorage();
      setToken(null);
      setUser(null);
      const from = { pathname: window.location.pathname, search: window.location.search };
      navigateRef.current('/login', { replace: true, state: { from } });
    });
    return () => setUnauthorizedHandler(null);
  }, []);

  // hasRole('ADMIN') or hasRole('ADMIN', 'OPERATOR'): true when the user has ANY of the roles.
  const hasRole = useCallback(
    (...roles) => {
      const wanted = roles.flat();
      const owned = user?.roles || [];
      return wanted.some((role) => owned.includes(role));
    },
    [user]
  );

  const value = useMemo(
    () => ({
      user,
      token,
      isAuthenticated: Boolean(token && user),
      hasRole,
      login,
      logout,
    }),
    [user, token, hasRole, login, logout]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used inside <AuthProvider>');
  }
  return context;
}
