// Task G1.5 | Group G1 (Train, Station & Route) | Route registry of the trains module.
//
// App.jsx loads every src/modules/*/routes.jsx and builds the router and the
// navigation bar from these entries:
//   path    URL of the page          label   text in the navigation (omit = no nav link)
//   order   position in navigation   roles   login needed + user must have one of these roles
//   public  true = no login needed   section grouping used by the navigation
// An entry with neither "roles" nor "public" needs any logged-in user.

import TrainSearchPage from './pages/TrainSearchPage.jsx';
import TrainListPage from './pages/TrainListPage.jsx';
import TrainTimetablePage from './pages/TrainTimetablePage.jsx';
import AdminTrainsPage from './pages/AdminTrainsPage.jsx';
import AdminStationsPage from './pages/AdminStationsPage.jsx';
import AdminRoutesPage from './pages/AdminRoutesPage.jsx';

const routes = [
  // ---- public pages ----
  {
    path: '/trains/search',
    element: <TrainSearchPage />,
    label: 'Search Trains',
    order: 10,
    public: true,
  },
  {
    path: '/trains',
    element: <TrainListPage />,
    label: 'Trains',
    order: 20,
    public: true,
  },
  {
    // No label: reached by the "View timetable" link of the train list.
    path: '/trains/:trainId',
    element: <TrainTimetablePage />,
    public: true,
  },

  // ---- administrator pages ----
  {
    path: '/admin/trains',
    element: <AdminTrainsPage />,
    label: 'Manage Trains',
    section: 'Admin',
    order: 110,
    roles: ['ADMIN'],
  },
  {
    path: '/admin/stations',
    element: <AdminStationsPage />,
    label: 'Manage Stations',
    section: 'Admin',
    order: 120,
    roles: ['ADMIN'],
  },
  {
    path: '/admin/routes',
    element: <AdminRoutesPage />,
    label: 'Manage Routes',
    section: 'Admin',
    order: 130,
    roles: ['ADMIN'],
  },
];

export default routes;
