// Task G4.5 (Group 4: Payment, Cancellation & Refund) - route registry of the payments module.
// App.jsx loads this file with import.meta.glob and builds the router and the navigation from it.
//   - no "roles" and no "public"  -> any logged-in user may open the page
//   - "label"                     -> the route also appears in the navigation
//   - "roles"                     -> login needed AND the user must have one of these roles
import PaymentPage from './pages/PaymentPage';
import CancelPage from './pages/CancelPage';
import PaymentHistoryPage from './pages/PaymentHistoryPage';
import AdminFaresPage from './pages/AdminFaresPage';

const routes = [
  // Reached from the booking flow (/book/... -> POST booking -> /payment/:bookingId)
  { path: '/payment/:bookingId', element: <PaymentPage /> },

  // Reached from /my-bookings (one link per passenger row)
  { path: '/cancel/:bookingPassengerId', element: <CancelPage /> },

  { path: '/payments/history', element: <PaymentHistoryPage />, label: 'Payments', section: 'Passenger', order: 40 },

  { path: '/admin/fares', element: <AdminFaresPage />, label: 'Manage Fares', section: 'Admin', order: 40, roles: ['ADMIN'] },
];

export default routes;
