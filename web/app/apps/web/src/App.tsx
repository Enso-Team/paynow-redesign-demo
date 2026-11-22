import { useEffect, useState } from "react";
import { useStore, type Screen } from "./lib/store";
import { session } from "./lib/session";
import { ensureDevice } from "./lib/device";
import { Entry, DigitalToken } from "./screens/Entry";
import { Scanner } from "./screens/Scanner";
import { PaynowMenu } from "./screens/PaynowMenu";
import { FormHost } from "./screens/FormHost";
import { Sent } from "./screens/Sent";
import { Placeholder } from "./screens/Placeholder";
import { Tabs } from "./screens/Tabs";
import { FaceIdSheet } from "./screens/FaceIdSheet";

function StatusBar({ tone }: { tone: "light" | "dark" }) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 15_000);
    return () => clearInterval(t);
  }, []);
  const time = `${now.getHours()}:${String(now.getMinutes()).padStart(2, "0")}`;
  return (
    <div className={`statusbar statusbar-${tone}`} aria-hidden>
      <span className="sb-time">{time}</span>
      <span className="sb-island" />
      <span className="sb-icons">
        <svg width="19" height="12" viewBox="0 0 19 12">
          <rect x="0" y="8" width="3.2" height="4" rx="1" fill="currentColor" />
          <rect x="5" y="5.5" width="3.2" height="6.5" rx="1" fill="currentColor" />
          <rect x="10" y="3" width="3.2" height="9" rx="1" fill="currentColor" />
          <rect x="15" y="0" width="3.2" height="12" rx="1" fill="currentColor" opacity=".35" />
        </svg>
        <svg width="17" height="12" viewBox="0 0 17 12">
          <path d="M8.5 2.2c2.5 0 4.8 1 6.5 2.6l1.2-1.3A10.8 10.8 0 0 0 8.5.4 10.8 10.8 0 0 0 .8 3.5L2 4.8a9 9 0 0 1 6.5-2.6Z" fill="currentColor" />
          <path d="M8.5 5.6c1.6 0 3 .6 4.1 1.6l1.2-1.3a7.8 7.8 0 0 0-10.6 0l1.2 1.3c1.1-1 2.5-1.6 4.1-1.6Z" fill="currentColor" />
          <path d="M8.5 9c.7 0 1.3.3 1.8.7L8.5 11.6 6.7 9.7c.5-.4 1.1-.7 1.8-.7Z" fill="currentColor" />
        </svg>
        <span className="sb-battery">
          <span className="sb-battery-level">66</span>
        </span>
      </span>
    </div>
  );
}

function tone(screen: Screen): "light" | "dark" {
  return screen.name === "entry" ? "light" : "dark";
}

function CurrentScreen({ screen }: { screen: Screen }) {
  switch (screen.name) {
    case "entry":
      return <Entry />;
    case "token":
      return <DigitalToken />;
    case "scanner":
      return <Scanner back={screen.back} />;
    case "paynowMenu":
      return <PaynowMenu back={screen.back} />;
    case "form":
      return <FormHost init={screen.init} back={screen.back} />;
    case "sent":
      return <Sent result={screen.result} />;
    case "placeholder":
      return <Placeholder title={screen.title} back={screen.back} />;
    case "tabs":
      return null;
  }
}

export function App() {
  const screen = useStore((s) => s.screen);
  const signedIn = useStore((s) => s.signedIn);
  const toast = useStore((s) => s.toast);

  useEffect(() => {
    ensureDevice().catch(() => undefined);
    const touch = () => session.touch();
    window.addEventListener("pointerdown", touch, true);
    window.addEventListener("keydown", touch, true);
    const keepAlive = setInterval(() => void session.keepAlive(), 30_000);
    return () => {
      window.removeEventListener("pointerdown", touch, true);
      window.removeEventListener("keydown", touch, true);
      clearInterval(keepAlive);
    };
  }, []);

  const tabsVisible = screen.name === "tabs";
  return (
    <div className="stage">
      <div className="phone">
        <div className="screen" data-testid="screen" data-screen={screen.name}>
          <StatusBar tone={tabsVisible ? "dark" : tone(screen)} />
          {signedIn && (
            <div className={tabsVisible ? "layer" : "layer layer-parked"} aria-hidden={!tabsVisible}>
              <Tabs active={tabsVisible} />
            </div>
          )}
          {!tabsVisible && (
            <div className="layer" key={screen.name}>
              <CurrentScreen screen={screen} />
            </div>
          )}
          {toast && (
            <div className="toast" role="status" data-testid="toast" key={toast.id}>
              {toast.text}
            </div>
          )}
          <FaceIdSheet />
          <div className="home-indicator" />
        </div>
      </div>
    </div>
  );
}
