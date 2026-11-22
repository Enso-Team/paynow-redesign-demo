import { go, type Screen } from "../lib/store";
import { Back } from "../icons";

export function Placeholder({ title, back }: { title: string; back: Screen }) {
  return (
    <div className="plain placeholder" data-testid="placeholder">
      <header className="navbar">
        <button className="navbar-left" aria-label="Back" onClick={() => go(back)}>
          <Back />
        </button>
        <h1>{title}</h1>
      </header>
      <div className="placeholder-body">
        <div className="placeholder-title">{title}</div>
        <p>This screen is a placeholder. The demo covers Log in, Scan &amp; Pay and PayNow.</p>
      </div>
    </div>
  );
}
