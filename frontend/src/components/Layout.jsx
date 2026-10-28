// Page frame: top navigation + content area + footer.
//
// The navigation is built from the route registry (see App.jsx). A route appears in the menu when
//   - it has a "label",
//   - its path has no ":param" (a link needs a concrete URL), and
//   - the current user may open it (public, or logged in, or has one of the route's roles).
// Links are sorted by "section" and then by "order".
import { useEffect, useMemo, useState } from 'react';
import { Link, NavLink, useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '@/auth/AuthContext';

// Sort helper: undefined goes last, numbers compare as numbers, everything else as text.
function compareValues(a, b) {
  const aMissing = a === undefined || a === null;
  const bMissing = b === undefined || b === null;
  if (aMissing && bMissing) return 0;
  if (aMissing) return 1;
  if (bMissing) return -1;
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  return String(a).localeCompare(String(b), undefined, { numeric: true });
}

function compareRoutes(a, b) {
  return (
    compareValues(a.section, b.section) ||
    compareValues(a.order, b.order) ||
    compareValues(a.label, b.label)
  );
}

const linkClass = ({ isActive }) =>
  `block rounded px-3 py-1.5 text-sm font-medium transition-colors ${
    isActive ? 'bg-white/20 text-white' : 'text-indigo-100 hover:bg-white/10 hover:text-white'
  }`;

export default function Layout({ routes = [], children }) {
  const { user, isAuthenticated, hasRole, logout } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [menuOpen, setMenuOpen] = useState(false);

  // Close the mobile menu after every navigation.
  useEffect(() => {
    setMenuOpen(false);
  }, [location.pathname]);

  const canOpen = (route) => {
    if (route.public) return true;
    if (!isAuthenticated) return false;
    if (Array.isArray(route.roles) && route.roles.length > 0) return hasRole(...route.roles);
    return true;
  };

  const navLinks = useMemo(
    () =>
      routes
        .filter((route) => route.label && typeof route.path === 'string' && !route.path.includes(':'))
        .filter(canOpen)
        .sort(compareRoutes),
    // canOpen depends on these three values
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [routes, isAuthenticated, user]
  );

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  // Login / Register links, or the user's name with a Logout button.
  const authControls = isAuthenticated ? (
    <div className="flex items-center gap-3">
      <span className="text-sm text-indigo-100">{user?.fullName || user?.email}</span>
      <button
        type="button"
        onClick={handleLogout}
        className="rounded border border-white/40 px-3 py-1 text-sm font-medium text-white hover:bg-white/10 focus:outline-none focus-visible:ring-2 focus-visible:ring-white"
      >
        Logout
      </button>
    </div>
  ) : (
    <div className="flex items-center gap-2">
      <NavLink to="/login" className={linkClass}>
        Login
      </NavLink>
      <NavLink to="/register" className={linkClass}>
        Register
      </NavLink>
    </div>
  );

  return (
    <div className="flex min-h-screen flex-col">
      <header className="bg-indigo-900 text-white shadow">
        <div className="mx-auto max-w-7xl px-4">
          <div className="flex h-14 items-center justify-between">
            <Link
              to="/"
              className="text-lg font-bold tracking-tight focus:outline-none focus-visible:ring-2 focus-visible:ring-white"
            >
              National Railway <span className="text-amber-300">Reservation</span>
            </Link>

            {/* Desktop: auth controls on the right */}
            <div className="hidden md:block">{authControls}</div>

            {/* Mobile: hamburger button */}
            <button
              type="button"
              className="rounded p-2 hover:bg-white/10 focus:outline-none focus-visible:ring-2 focus-visible:ring-white md:hidden"
              aria-label="Toggle navigation menu"
              aria-expanded={menuOpen}
              aria-controls="main-nav"
              onClick={() => setMenuOpen((open) => !open)}
            >
              <svg className="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                {menuOpen ? (
                  <path strokeLinecap="round" d="M6 6l12 12M18 6L6 18" />
                ) : (
                  <path strokeLinecap="round" d="M4 6h16M4 12h16M4 18h16" />
                )}
              </svg>
            </button>
          </div>

          {/* Navigation links: always visible on desktop, toggled by the hamburger on mobile */}
          <nav id="main-nav" aria-label="Main navigation" className={`${menuOpen ? 'block' : 'hidden'} pb-3 md:block`}>
            <ul className="flex flex-col gap-1 md:flex-row md:flex-wrap">
              {navLinks.map((route) => (
                <li key={route.path}>
                  <NavLink to={route.path} className={linkClass}>
                    {route.label}
                  </NavLink>
                </li>
              ))}
            </ul>
            <div className="mt-3 border-t border-white/20 pt-3 md:hidden">{authControls}</div>
          </nav>
        </div>
      </header>

      <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6">{children}</main>

      <footer className="border-t border-slate-200 bg-white py-4 text-center text-xs text-slate-500">
        National Railway Reservation &amp; Management System &mdash; college DBMS project
      </footer>
    </div>
  );
}
