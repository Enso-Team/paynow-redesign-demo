import { useEffect, useRef, useState, type CSSProperties } from "react";
import { dispatch, type Intent } from "../lib/router";
import { go } from "../lib/store";
import { formatAsOf, formatDay, formatSigned, peek, peekTiming, type PeekBalance } from "../lib/peek";
import { Bell, Chat, Close } from "../icons";
import { asset, DEMO, PRIVACY_NOTE } from "../lib/demo";

const TILES: { label: string; img: string; intent?: Intent; to?: "token" }[] = [
  { label: "Log In", img: "entry-login", intent: { kind: "login" } },
  { label: "Digital Token", img: "entry-token", to: "token" },
  { label: "PayNow", img: "entry-paynow", intent: { kind: "payNow" } },
  { label: "Overseas\nTransfer", img: "entry-overseas", intent: { kind: "overseas" } },
  { label: "Scan & Pay", img: "entry-scan", intent: { kind: "scanAndPay" } },
  { label: "Apply & More\nServices", img: "entry-apply", intent: { kind: "apply" } },
];

type PeekPhase = "off" | "slide" | "bars" | "blank" | "compact" | "expanded" | "leaving";

/** Stage lengths: card slides up, two grey bars, an empty card, then the balance. */
const PEEK_MS = { slide: 150, bars: 500, blank: 800, fade: 200, cachedCompact: 600, leave: 300 };

/**
 * Tap and hold: the entry page blurs in place and the Peek card rises above the hint.
 * The first hold runs the skeleton while the read-only pass fetches. A repeat hold within a minute
 * shows the balance on its first frame. Release puts the entry page back.
 */
function usePeekHold() {
  const [phase, setPhase] = useState<PeekPhase>("off");
  const [data, setData] = useState<PeekBalance | null>(null);
  const [failed, setFailed] = useState(false);
  const [instant, setInstant] = useState(false);
  const holding = useRef(false);
  const run = useRef(0);
  const timers = useRef<number[]>([]);

  const clear = () => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
  };
  const after = (ms: number, fn: () => void) => {
    timers.current.push(window.setTimeout(fn, ms * peekTiming.scale));
  };
  useEffect(() => clear, []);

  const start = () => {
    if (holding.current) return;
    holding.current = true;
    clear();
    const id = ++run.current;
    setFailed(false);
    const hit = peek.cached();
    if (hit) {
      setData(hit);
      setInstant(true);
      setPhase("compact");
      after(PEEK_MS.cachedCompact, () => setPhase("expanded"));
      return;
    }
    setData(null);
    setInstant(false);
    setPhase("slide");
    const result = peek.load().then(
      (d) => ({ ok: true as const, d }),
      () => ({ ok: false as const }),
    );
    after(PEEK_MS.slide, () => setPhase("bars"));
    after(PEEK_MS.slide + PEEK_MS.bars, () => setPhase("blank"));
    after(PEEK_MS.slide + PEEK_MS.bars + PEEK_MS.blank, async () => {
      const r = await result;
      if (run.current !== id) return;
      if (!r.ok) {
        setFailed(true);
        setPhase("compact");
        return;
      }
      setData(r.d);
      setPhase("compact");
      after(PEEK_MS.fade, () => setPhase("expanded"));
    });
  };

  const end = () => {
    if (!holding.current) return;
    holding.current = false;
    clear();
    run.current++;
    setPhase("leaving");
    after(PEEK_MS.leave, () => setPhase("off"));
  };

  return { phase, data, failed, instant, start, end };
}

function PeekOverlay({ phase, data, failed, instant }: { phase: PeekPhase; data: PeekBalance | null; failed: boolean; instant: boolean }) {
  // The blur and veil fade in over 0.3 s from the frame after mount, and fade out while "leaving" keeps them mounted.
  const [veilOn, setVeilOn] = useState(false);
  useEffect(() => {
    if (phase === "off") return setVeilOn(false);
    if (phase === "leaving") return setVeilOn(false);
    const raf = requestAnimationFrame(() => setVeilOn(true));
    return () => cancelAnimationFrame(raf);
  }, [phase]);
  if (phase === "off") return null;
  const shown = phase === "compact" || phase === "expanded";
  return (
    <div
      className="peek-overlay"
      data-phase={phase}
      data-veil={veilOn ? "on" : "off"}
      data-testid="peek-overlay"
      style={{ "--peek-scale": peekTiming.scale } as CSSProperties}
      aria-live="polite"
    >
      <div className="peek-veil" />
      {phase !== "leaving" && (
        <div className={instant ? "peek-card peek-card-instant" : "peek-card"} data-testid="peek-card">
          {phase === "bars" && (
            <div className="peek-bars" data-testid="peek-skeleton">
              <span />
              <span />
            </div>
          )}
          {shown && failed && <div className="peek-failed">Couldn't load your balance. Try again.</div>}
          {shown && data && (
            <div className="peek-content">
              <div className="peek-label">Deposit balance</div>
              <div className="peek-amount" data-testid="peek-balance">
                <span className="peek-ccy">{data.currency}</span> {data.balance}
              </div>
              <div className="peek-more">
                <div>
                  <div className="peek-asof">As of {formatAsOf(data.asOf)}</div>
                  <div className="peek-tx-title">Latest transactions (within last 30 days)</div>
                  {data.transactions.map((t, i) => (
                    <div className="peek-tx" key={i} data-testid="peek-tx">
                      <div>
                        <div className="peek-tx-type">{t.type}</div>
                        <div className="peek-tx-date">{formatDay(t.date)}</div>
                      </div>
                      <div className="peek-tx-amount">{formatSigned(t.amount)}</div>
                    </div>
                  ))}
                  {data.transactions.length === 0 && <div className="peek-tx-none">No transactions in the last 30 days</div>}
                </div>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export function Entry() {
  const hold = usePeekHold();
  const peeking = hold.phase !== "off";

  return (
    <div className="entry">
      <div className="entry-hero">
        <div className="entry-top">
          <span className="entry-bell">
            <Bell size={30} />
            <span className="badge badge-red">45</span>
          </span>
          <Chat size={30} />
        </div>
        <div className="entry-alert">
          <div className="entry-alert-text">
            Notice: This is a concept demo. No real money moves. Never share your OTP or password with anyone.
          </div>
          <span className="entry-alert-bar" />
        </div>
        <button
          className={peeking ? "entry-peek entry-peek-on" : "entry-peek"}
          data-testid="peek"
          onPointerDown={hold.start}
          onPointerUp={hold.end}
          onPointerLeave={hold.end}
          onPointerCancel={hold.end}
          onKeyDown={(e) => (e.key === " " || e.key === "Enter") && !e.repeat && hold.start()}
          onKeyUp={(e) => (e.key === " " || e.key === "Enter") && hold.end()}
          onBlur={hold.end}
          onContextMenu={(e) => e.preventDefault()}
        >
          <span className="entry-peek-chev">〉</span>
          <span>
            <span className="entry-peek-small">Tap and hold to</span>
            <span className="entry-peek-big">PEEK BALANCE</span>
          </span>
          <span className="entry-peek-chev">〈</span>
        </button>
        <div className="entry-grid">
          {TILES.map((t) => (
            <button
              key={t.img}
              className="entry-tile"
              data-testid={`tile-${t.img.replace("entry-", "")}`}
              onClick={() => (t.intent ? void dispatch(t.intent) : t.to && go({ name: t.to }))}
            >
              <img src={asset(`img/${t.img}.png`)} alt="" className={`entry-icon entry-icon-${t.img}`} />
              <span className="entry-label">{t.label}</span>
            </button>
          ))}
        </div>
      </div>
      <div className="entry-sheet">
        <span className="entry-handle" />
        {DEMO && (
          <div className="demo-note demo-note-entry" data-testid="privacy-note">
            {PRIVACY_NOTE}
          </div>
        )}
        <div className="promo">
          <img src={asset("img/promo-child.jpg")} alt="" />
          <div className="promo-text">
            <div className="promo-title">Save for What's Next</div>
            <div className="promo-sub">Set a goal and watch your savings grow.</div>
          </div>
        </div>
      </div>
      <PeekOverlay phase={hold.phase} data={hold.data} failed={hold.failed} instant={hold.instant} />
    </div>
  );
}

export function DigitalToken() {
  const [otp, setOtp] = useState<string | null>(null);
  return (
    <div className="plain">
      <header className="navbar navbar-flat">
        <button className="navbar-left" aria-label="Close" onClick={() => go({ name: "entry" })}>
          <Close />
        </button>
        <h1>Digital Token</h1>
      </header>
      <div className="token">
        <img src={asset("img/token-lock.png")} alt="" className="token-lock" />
        <div className="token-title">One-time PIN (OTP)</div>
        {otp ? (
          <div className="token-otp" data-testid="otp">
            {otp.slice(0, 3)} {otp.slice(3)}
          </div>
        ) : null}
        <button
          className="token-btn"
          onClick={() => setOtp(String(Math.floor(100000 + Math.random() * 900000)))}
        >
          GENERATE OTP
        </button>
      </div>
    </div>
  );
}
