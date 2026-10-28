// Shown for any URL that no route matches.
import { Link, useLocation } from 'react-router-dom';
import { PageHeader } from '@/components/ui';

export default function NotFound() {
  const location = useLocation();

  return (
    <div>
      <PageHeader title="Page not found" subtitle="Error 404" />
      <p className="text-sm text-slate-700">
        There is nothing at <code className="rounded bg-slate-100 px-1 py-0.5">{location.pathname}</code>.
      </p>
      <Link to="/" className="mt-4 inline-block text-sm font-medium text-indigo-700 hover:underline">
        Go to the home page
      </Link>
    </div>
  );
}
