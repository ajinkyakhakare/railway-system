// G3.5 - Route registry of the booking module.
// App.jsx loads this file with import.meta.glob and reads the default export.
// Fields: path, element, label (shows in navigation), section, order,
//         roles (login + one of these roles), public (no login needed).
// A route without "roles" and without "public" needs any logged-in user.
import AvailabilityPage from './pages/AvailabilityPage.jsx';
import BookingPage from './pages/BookingPage.jsx';
import MyBookingsPage from './pages/MyBookingsPage.jsx';
import TicketLookupPage from './pages/TicketLookupPage.jsx';
import TicketPage from './pages/TicketPage.jsx';
import SeatMapPage from './pages/SeatMapPage.jsx';
import AdminOccupancyPage from './pages/AdminOccupancyPage.jsx';

const routes = [
  // Seat availability of one train run, reached from the train search result.
  {
    path: '/availability/:runId',
    element: <AvailabilityPage />,
    public: true,
  },
  // Booking form: choose passengers, see the fare quote, book.
  {
    path: '/book/:runId/:classCode',
    element: <BookingPage />,
  },
  // The logged-in user's bookings.
  {
    path: '/my-bookings',
    element: <MyBookingsPage />,
    label: 'My Bookings',
    section: 'Booking',
    order: 10,
  },
  // Public PNR lookup form.
  {
    path: '/tickets',
    element: <TicketLookupPage />,
    label: 'PNR Status',
    section: 'Booking',
    order: 20,
    public: true,
  },
  // Public PNR status card.
  {
    path: '/tickets/:pnr',
    element: <TicketPage />,
    public: true,
  },
  // Coach-wise seat map of one run and class.
  {
    path: '/seat-map/:runId/:classCode',
    element: <SeatMapPage />,
    public: true,
  },
  // Admin: occupancy per run and class for one date.
  {
    path: '/admin/occupancy',
    element: <AdminOccupancyPage />,
    label: 'Occupancy',
    section: 'Admin',
    order: 30,
    roles: ['ADMIN'],
  },
];

export default routes;
