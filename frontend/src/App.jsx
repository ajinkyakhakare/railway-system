// Builds the whole route table from the modules that exist.
//
// Every module owns src/modules/<folder>/routes.jsx whose default export is an array like
//   [{ path: '/trains/search', element: <SearchPage />, label: 'Search Trains', section: 1, order: 1,
//      public: true }, ...]
// import.meta.glob finds all of those files at build time, so a module can be added or removed
// without editing this file. With zero modules the app still shows Home and NotFound.
import { Route, Routes } from 'react-router-dom';
import Layout from '@/components/Layout';
import RequireAuth from '@/auth/RequireAuth';
import Home from '@/pages/Home';
import NotFound from '@/pages/NotFound';

const moduleFiles = import.meta.glob('./modules/*/routes.jsx', { eager: true });

// Join the default export (an array) of every routes.jsx and drop anything that is not a valid route.
const allRoutes = Object.values(moduleFiles)
  .flatMap((moduleFile) => (Array.isArray(moduleFile.default) ? moduleFile.default : []))
  .filter((route) => route && typeof route.path === 'string' && route.path !== '/' && route.element);

// public:true -> anyone; roles -> login + one of the roles; otherwise -> any logged-in user.
function guard(route) {
  if (route.public) return route.element;
  return <RequireAuth roles={route.roles}>{route.element}</RequireAuth>;
}

export default function App() {
  return (
    <Layout routes={allRoutes}>
      <Routes>
        <Route path="/" element={<Home />} />
        {allRoutes.map((route) => (
          <Route key={route.path} path={route.path} element={guard(route)} />
        ))}
        <Route path="*" element={<NotFound />} />
      </Routes>
    </Layout>
  );
}
