import { getState, setState } from "./store";

export const FACE_ID_MS = 1200;

let queue: Promise<unknown> = Promise.resolve();

/** Shows the mocked Face ID sheet for a journey. Resolves true on success, false when cancelled. */
export function askFaceId(label: string): Promise<boolean> {
  const run = () =>
    new Promise<boolean>((resolve) => {
      setState({
        faceId: {
          label,
          resolve: (ok) => {
            if (getState().faceId?.resolve) setState({ faceId: null });
            resolve(ok);
          },
        },
      });
    });
  const next = queue.then(run, run);
  queue = next.catch(() => undefined);
  return next;
}
