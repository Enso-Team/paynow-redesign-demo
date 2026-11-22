import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { Form } from "./Form";
import type { PaynowInit } from "./bridge";
import { installMockHost } from "./mockHost";
import "./styles.css";

let openForm: ((init: PaynowInit) => void) | null = null;
let queued: PaynowInit | null = null;

window.paynowForm = {
  open(init) {
    if (openForm) openForm(init);
    else queued = init;
  },
};

function App() {
  const [session, setSession] = useState<{ id: number; init: PaynowInit } | null>(() => {
    const init = queued ?? window.__PAYNOW_INIT__;
    return init ? { id: 1, init } : null;
  });
  const first = session?.init;
  useEffect(() => {
    openForm = (init) => setSession((s) => ({ id: (s?.id ?? 0) + 1, init }));
    if (queued && queued !== first) openForm(queued);
    queued = null;
    return () => {
      openForm = null;
    };
  }, []);
  if (!session) return null;
  return <Form key={session.id} init={session.init} />;
}

function start() {
  if (new URLSearchParams(location.search).has("mock") && !window.paynowHost) installMockHost();
  createRoot(document.getElementById("root")!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}

start();
