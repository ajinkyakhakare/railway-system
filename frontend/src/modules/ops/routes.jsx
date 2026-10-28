// G5 (Railway Operations & Analytics) - route registry.
// App.jsx loads this file with import.meta.glob and builds the router + navigation from it:
//   label  -> the route appears in the navigation bar
//   public -> no login needed
//   roles  -> login needed and the user must have one of these roles
import LiveBoardPage from './pages/LiveBoardPage.jsx';
import StatusUpdatePage from './pages/StatusUpdatePage.jsx';
import DashboardPage from './pages/DashboardPage.jsx';
import RevenueReportPage from './pages/RevenueReportPage.jsx';
import PopularRoutesPage from './pages/PopularRoutesPage.jsx';
import DelayReportPage from './pages/DelayReportPage.jsx';

const routes = [
  { path: '/ops/board', element: <LiveBoardPage />, label: 'Live Board', order: 10, public: true },
  {
    path: '/ops/update',
    element: <StatusUpdatePage />,
    label: 'Update Status',
    order: 20,
    roles: ['OPERATOR', 'ADMIN'],
  },
  {
    path: '/admin/dashboard',
    element: <DashboardPage />,
    label: 'Dashboard',
    order: 30,
    roles: ['ADMIN'],
  },
  {
    path: '/admin/reports/revenue',
    element: <RevenueReportPage />,
    label: 'Revenue',
    order: 40,
    roles: ['ADMIN'],
  },
  {
    path: '/admin/reports/routes',
    element: <PopularRoutesPage />,
    label: 'Popular Routes',
    order: 50,
    roles: ['ADMIN'],
  },
  {
    path: '/admin/reports/delays',
    element: <DelayReportPage />,
    label: 'Delays',
    order: 60,
    roles: ['ADMIN'],
  },
];

export default routes;
