import { useEffect, useState } from "react";
import { useStore } from "../lib/store";
import { FACE_ID_MS } from "../lib/faceid";
import { FaceGlyph } from "../icons";

/** The mocked Face ID HUD: the glyph scans, turns into a tick, and the sheet closes after about 1.2 s. */
export function FaceIdSheet() {
  const req = useStore((s) => s.faceId);
  const [phase, setPhase] = useState<"scan" | "ok">("scan");

  useEffect(() => {
    if (!req) return;
    setPhase("scan");
    const t1 = setTimeout(() => setPhase("ok"), FACE_ID_MS * 0.62);
    const t2 = setTimeout(() => req.resolve(true), FACE_ID_MS);
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && req.resolve(false);
    window.addEventListener("keydown", onKey);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
      window.removeEventListener("keydown", onKey);
    };
  }, [req]);

  if (!req) return null;
  return (
    <div className="faceid-backdrop" data-testid="faceid" onClick={() => req.resolve(false)}>
      <div
        className={`faceid-hud faceid-${phase}`}
        role="dialog"
        aria-label={`Face ID for ${req.label}`}
        onClick={(e) => e.stopPropagation()}
      >
        <FaceGlyph className="faceid-glyph" />
        <div className="faceid-title">Face ID</div>
        <div className="faceid-reason">{req.label}</div>
      </div>
      <button className="faceid-cancel" onClick={() => req.resolve(false)} data-testid="faceid-cancel">
        Cancel
      </button>
    </div>
  );
}
