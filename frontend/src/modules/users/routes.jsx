// G2.5 - Users module route registry (frontend/src/modules/users/routes.jsx)
// App.jsx loads this file with import.meta.glob('./modules/*/routes.jsx').
// Entries with a "label" appear in the navigation bar.
//   public: true  -> no login needed
//   roles: [...]  -> login needed and the user must have one of the roles
//   (neither)     -> any logged-in user
import LoginPage from "./pages/LoginPage.jsx";
import RegisterPage from "./pages/RegisterPage.jsx";
import ProfilePage from "./pages/ProfilePage.jsx";
import PassengersPage from "./pages/PassengersPage.jsx";
import AdminUsersPage from "./pages/AdminUsersPage.jsx";

const routes = [
  { path: "/login", element: <LoginPage />, public: true },
  { path: "/register", element: <RegisterPage />, public: true },
  {
    path: "/profile",
    element: <ProfilePage />,
    label: "My Profile",
    section: "Account",
    order: 10,
  },
  {
    path: "/passengers",
    element: <PassengersPage />,
    label: "My Passengers",
    section: "Account",
    order: 20,
  },
  {
    path: "/admin/users",
    element: <AdminUsersPage />,
    label: "Manage Users",
    section: "Admin",
    order: 10,
    roles: ["ADMIN"],
  },
];

export default routes;
