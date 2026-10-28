// useAsync(asyncFn, deps) runs asyncFn when the component mounts and again whenever
// one of the values in deps changes. Call reload() to run it again manually.
//
//   const { data, loading, error, reload } = useAsync(() => client.get('/trains'), []);
//
// error is an ApiError (see api/client.js) or null.
import { useCallback, useEffect, useRef, useState } from 'react';

export function useAsync(asyncFn, deps = []) {
  const [state, setState] = useState({ data: null, loading: true, error: null });
  const [reloadCount, setReloadCount] = useState(0);

  // Always call the newest version of asyncFn without making it a dependency.
  const fnRef = useRef(asyncFn);
  fnRef.current = asyncFn;

  useEffect(() => {
    // "cancelled" stops an old request from overwriting the result of a newer one
    // (or from updating a component that has already been removed).
    let cancelled = false;
    setState((previous) => ({ ...previous, loading: true, error: null }));

    (async () => {
      try {
        const data = await fnRef.current();
        if (!cancelled) setState({ data, loading: false, error: null });
      } catch (error) {
        if (!cancelled) setState({ data: null, loading: false, error });
      }
    })();

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, reloadCount]);

  const reload = useCallback(() => setReloadCount((count) => count + 1), []);

  return { data: state.data, loading: state.loading, error: state.error, reload };
}
