// Route guard.
//  - not logged in            -> redirect to /login (the page they wanted is kept in location.state.from)
//  - logged in, wrong role    -> "Access denied" message
//  - otherwise                -> render the page
import { Link, Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/auth/AuthContext';
import { Alert } from '@/components/ui/Alert';
import { PageHeader } from '@/components/ui/PageHeader';

export default function RequireAuth({ roles, children }) {
  const { isAuthenticated, hasRole } = useAuth();
  const location = useLocation();

  if (!isAuthenticated) {
    return <Navigate to="/login" replace state={{ from: location }} />;
  }

  const needsRole = Array.isArray(roles) && roles.length > 0;
  if (needsRole && !hasRole(...roles)) {
    return (
      <div>
        <PageHeader title="Access denied" />
        <Alert tone="error">You do not have permission to open this page.</Alert>
        <Link to="/" className="mt-4 inline-block text-sm font-medium text-indigo-700 hover:underline">
          Back to home
        </Link>
      </div>
    );
  }

  return children;
}
