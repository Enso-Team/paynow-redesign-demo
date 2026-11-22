import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { session } from "./lib/session";
import { getState } from "./lib/store";
import { peekTiming } from "./lib/peek";
import { DEMO } from "./lib/demo";
import "./styles.css";

const fitScreen = () =>
  document.documentElement.style.setProperty("--fit", String(Math.min(1, innerWidth / 390, innerHeight / 844)));
fitScreen();
addEventListener("resize", fitScreen);

Object.assign(window, {
  __dbsDemo: {
    state: getState,
    expireAccessToken: () => session.debugExpireAccess(),
    goIdle: () => session.debugIdle(),
    peekTimeScale: (scale: number) => (peekTiming.scale = scale),
  },
});

// The public demo answers /api in the browser, so it has to be in place before the app binds its device.
if (DEMO) (await import("./demo/install")).installDemoBackend();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
