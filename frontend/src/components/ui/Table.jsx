// Simple data table.
//   columns: [{ key, header, render?(row) }]   render is optional; without it row[key] is shown
//   rows:    array of objects
//   rowKey:  name of a unique field (e.g. "trainId") or a function (row) => key
//   emptyText: message shown when rows is empty
// The table scrolls sideways on small screens instead of breaking the page layout.
function cellText(value) {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  return String(value);
}

export function Table({ columns = [], rows = [], rowKey, emptyText = 'No records found.' }) {
  const getKey = (row, index) => {
    if (typeof rowKey === 'function') return rowKey(row);
    if (typeof rowKey === 'string' && row[rowKey] !== undefined) return row[rowKey];
    return index;
  };

  return (
    <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
      <table className="min-w-full divide-y divide-slate-200 text-sm">
        <thead className="bg-slate-100">
          <tr>
            {columns.map((column) => (
              <th
                key={column.key}
                scope="col"
                className="whitespace-nowrap px-4 py-2 text-left font-semibold text-slate-700"
              >
                {column.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {rows.length === 0 ? (
            <tr>
              <td colSpan={columns.length || 1} className="px-4 py-6 text-center text-slate-500">
                {emptyText}
              </td>
            </tr>
          ) : (
            rows.map((row, index) => (
              <tr key={getKey(row, index)} className="hover:bg-slate-50">
                {columns.map((column) => (
                  <td key={column.key} className="whitespace-nowrap px-4 py-2 text-slate-800">
                    {column.render ? column.render(row) : cellText(row[column.key])}
                  </td>
                ))}
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}
