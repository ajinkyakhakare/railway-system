// G2.5 - Admin "Manage Users" page (frontend/src/modules/users/pages/AdminUsersPage.jsx)
// Shows every user (rows of view v_user_account). The admin can tick roles and press
// Save for one row (PUT /admin/users/{id}/roles) or switch the account on / off
// (PUT /admin/users/{id}/active).
import { useEffect, useState } from "react";
import { useAuth } from "@/auth/AuthContext";
import { useAsync } from "@/hooks/useAsync";
import { Alert, Badge, Button, Card, PageHeader, Spinner, Table } from "@/components/ui";
import { formatDateTime } from "@/utils/format";
import { listUsers, setUserActive, updateUserRoles } from "../api";

const ALL_ROLES = ["PASSENGER", "ADMIN", "OPERATOR"];

// The view returns roles as one string such as "ADMIN,PASSENGER".
function parseRoles(rolesText) {
  if (!rolesText) return [];
  return String(rolesText)
    .split(",")
    .map((role) => role.trim())
    .filter(Boolean);
}

// Same set of roles, ignoring order?
function sameRoles(a, b) {
  return a.length === b.length && a.every((role) => b.includes(role));
}

export default function AdminUsersPage() {
  const { user: currentUser } = useAuth();
  const { data, loading, error: loadError } = useAsync(() => listUsers(), []);

  // Local copy of the rows so a save can update one row without reloading the table.
  const [users, setUsers] = useState([]);
  // Unsaved role ticks: { [userId]: ["ADMIN", ...] }. A missing key = no unsaved change.
  const [draftRoles, setDraftRoles] = useState({});
  const [busyUserId, setBusyUserId] = useState(null);
  const [success, setSuccess] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    if (data) setUsers(data);
  }, [data]);

  // Roles currently shown as ticked for a row (draft first, else saved roles).
  function shownRoles(row) {
    return draftRoles[row.userId] ?? parseRoles(row.roles);
  }

  // The logged-in admin cannot lock themselves out from this screen.
  function isSelf(row) {
    return currentUser && Number(currentUser.userId) === Number(row.userId);
  }

  function toggleRole(row, role) {
    const current = shownRoles(row);
    const next = current.includes(role)
      ? current.filter((r) => r !== role)
      : [...current, role];
    setDraftRoles((previous) => ({ ...previous, [row.userId]: next }));
    setSuccess("");
    setError("");
  }

  async function saveRoles(row) {
    const roles = ALL_ROLES.filter((role) => shownRoles(row).includes(role));
    setBusyUserId(row.userId);
    setSuccess("");
    setError("");
    try {
      const result = await updateUserRoles(row.userId, roles);
      setUsers((previous) =>
        previous.map((u) =>
          u.userId === row.userId ? { ...u, roles: result.roles.join(",") } : u
        )
      );
      setDraftRoles((previous) => {
        const copy = { ...previous };
        delete copy[row.userId];
        return copy;
      });
      setSuccess(`Roles saved for ${row.fullName}.`);
    } catch (err) {
      setError(err.message || "Could not save the roles.");
    } finally {
      setBusyUserId(null);
    }
  }

  async function toggleActive(row) {
    const nextActive = !row.isActive;
    setBusyUserId(row.userId);
    setSuccess("");
    setError("");
    try {
      const result = await setUserActive(row.userId, nextActive);
      setUsers((previous) =>
        previous.map((u) =>
          u.userId === row.userId ? { ...u, isActive: Boolean(result.active) } : u
        )
      );
      setSuccess(`${row.fullName} is now ${result.active ? "active" : "deactivated"}.`);
    } catch (err) {
      setError(err.message || "Could not change the account status.");
    } finally {
      setBusyUserId(null);
    }
  }

  const columns = [
    {
      key: "fullName",
      header: "User",
      render: (row) => (
        <div>
          <div className="font-medium text-gray-900">{row.fullName}</div>
          <div className="text-sm text-gray-500">{row.email}</div>
          <div className="text-sm text-gray-500">{row.phone}</div>
        </div>
      ),
    },
    {
      key: "roles",
      header: "Roles",
      render: (row) => {
        const ticked = shownRoles(row);
        return (
          <div className="flex flex-wrap gap-x-4 gap-y-1">
            {ALL_ROLES.map((role) => (
              <label key={role} className="flex items-center gap-1.5 text-sm text-gray-700">
                <input
                  type="checkbox"
                  className="h-4 w-4 rounded border-gray-300"
                  checked={ticked.includes(role)}
                  // Own ADMIN role stays ticked so the admin cannot remove their own access.
                  disabled={busyUserId === row.userId || (isSelf(row) && role === "ADMIN")}
                  onChange={() => toggleRole(row, role)}
                />
                {role}
              </label>
            ))}
          </div>
        );
      },
    },
    {
      key: "isActive",
      header: "Status",
      render: (row) => (
        <Badge tone={row.isActive ? "green" : "red"}>
          {row.isActive ? "Active" : "Deactivated"}
        </Badge>
      ),
    },
    {
      key: "createdAt",
      header: "Created",
      render: (row) => formatDateTime(row.createdAt),
    },
    {
      key: "actions",
      header: "Actions",
      render: (row) => {
        const ticked = shownRoles(row);
        const changed = !sameRoles(ticked, parseRoles(row.roles));
        const busy = busyUserId === row.userId;
        return (
          <div className="flex flex-wrap gap-2">
            <Button
              onClick={() => saveRoles(row)}
              loading={busy}
              // At least one role is required by the server.
              disabled={!changed || ticked.length === 0 || busyUserId !== null}
            >
              Save roles
            </Button>
            <Button
              variant={row.isActive ? "danger" : "secondary"}
              onClick={() => toggleActive(row)}
              disabled={isSelf(row) || busyUserId !== null}
            >
              {row.isActive ? "Deactivate" : "Activate"}
            </Button>
          </div>
        );
      },
    },
  ];

  return (
    <div>
      <PageHeader
        title="Manage Users"
        subtitle="Change roles and switch accounts on or off. At least one role is required per user."
      />

      {success && (
        <div className="mb-4">
          <Alert tone="success">{success}</Alert>
        </div>
      )}
      {error && (
        <div className="mb-4">
          <Alert tone="error">{error}</Alert>
        </div>
      )}
      {loadError && (
        <div className="mb-4">
          <Alert tone="error">{loadError.message || "Could not load the users."}</Alert>
        </div>
      )}

      {loading && !data ? (
        <div className="flex justify-center py-12">
          <Spinner />
        </div>
      ) : (
        <Card>
          <Table
            columns={columns}
            rows={users}
            rowKey="userId"
            emptyText="No users found."
          />
        </Card>
      )}
    </div>
  );
}
