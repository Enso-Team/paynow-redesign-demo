import { useEffect, useState, type ReactNode } from "react";
import { refreshAccounts, totalAvailable, formatMoney, useAccounts } from "../lib/accounts";
import { dispatch, signOut } from "../lib/router";
import { go, setState, useStore, type TabId } from "../lib/store";
import { Bell, Chat, ChevronDown, ChevronRight, Eye, Gear, Plus, Search, Warning } from "../icons";
import { asset, DEMO, PRIVACY_NOTE, resetDemo, TIMING_NOTE } from "../lib/demo";

const TABS: { id: TabId; label: string; icon: string; on: string }[] = [
  { id: "home", label: "Home", icon: "tab-home", on: "tab-home-on" },
  { id: "pay", label: "Pay & Transfer", icon: "tab-pay", on: "tab-pay-on" },
  { id: "wealth", label: "Wealth", icon: "tab-wealth", on: "tab-wealth" },
  { id: "apply", label: "Apply", icon: "tab-apply", on: "tab-apply-on" },
  { id: "more", label: "More", icon: "tab-more", on: "tab-more-on" },
];

const HIDE_KEY = "dbs.hideBalance";
const REFRESH_MS = 60_000;

function soon(title: string) {
  go({ name: "placeholder", title, back: { name: "tabs" } });
}

export function Tabs({ active }: { active: boolean }) {
  const tab = useStore((s) => s.tab);

  useEffect(() => {
    if (!active) return;
    void refreshAccounts({ interactive: false });
    const t = setInterval(() => void refreshAccounts({ interactive: false }), REFRESH_MS);
    return () => clearInterval(t);
  }, [active]);

  return (
    <div className="tabs">
      {TABS.map((t) => (
        <div key={t.id} className={`pane ${tab === t.id ? "pane-on" : ""}`} data-testid={`pane-${t.id}`}>
          {t.id === "home" && <Home />}
          {t.id === "pay" && <PayTransfer />}
          {t.id === "wealth" && <Wealth />}
          {t.id === "apply" && <Apply />}
          {t.id === "more" && <More />}
        </div>
      ))}
      <nav className="tabbar" aria-label="Tabs">
        {TABS.map((t) => (
          <button
            key={t.id}
            className={`tabbar-item ${tab === t.id ? "tabbar-on" : ""}`}
            aria-current={tab === t.id ? "page" : undefined}
            data-testid={`tab-${t.id}`}
            onClick={() => {
              setState({ tab: t.id });
              if (t.id === "home") void refreshAccounts({ interactive: false });
            }}
          >
            <span className="tabbar-icon" style={{ maskImage: `url(${asset(`img/${tab === t.id ? t.on : t.icon}.png`)})`, WebkitMaskImage: `url(${asset(`img/${tab === t.id ? t.on : t.icon}.png`)})` }} />
            <span className="tabbar-label">{t.label}</span>
          </button>
        ))}
      </nav>
    </div>
  );
}

function useHideBalance(): [boolean, () => void] {
  const [hide, setHide] = useState(() => localStorage.getItem(HIDE_KEY) === "1");
  useEffect(() => {
    const onStorage = (e: StorageEvent) => e.key === HIDE_KEY && setHide(e.newValue === "1");
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);
  return [
    hide,
    () =>
      setHide((h) => {
        localStorage.setItem(HIDE_KEY, h ? "0" : "1");
        return !h;
      }),
  ];
}

function useMinutesSince(ts: number | null) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 15_000);
    return () => clearInterval(t);
  }, []);
  return ts == null ? null : Math.max(1, Math.round((now - ts) / 60_000));
}

function Shortcut({ img, label, onClick, testId }: { img: string; label: string; onClick: () => void; testId?: string }) {
  return (
    <button className="shortcut" onClick={onClick} data-testid={testId}>
      <img src={asset(`img/${img}.png`)} alt="" />
      <span>{label}</span>
    </button>
  );
}

function Home() {
  const acc = useAccounts();
  const [hide, toggleHide] = useHideBalance();
  const [showAll, setShowAll] = useState(false);
  const minutes = useMinutesSince(acc.lastSuccess);
  const name = acc.summary?.displayName ?? "ALEX TAN";
  const dots = "••••••";

  return (
    <div className="scroll home">
      <div className="home-hero">
        <span className="hero-bubble hero-bubble-a" />
        <span className="hero-bubble hero-bubble-b" />
        <div className="home-top">
          <span className="icon-badge">
            <Bell size={30} />
            <span className="badge badge-dark">51</span>
          </span>
          <span className="home-top-right">
            <Chat size={30} />
            <button className="logout-pill" onClick={signOut} data-testid="logout">
              LOG OUT
            </button>
          </span>
        </div>
        <div className="home-hi" data-testid="greeting">
          Hi, {name}!
        </div>
        <div className="home-networth">
          View your net worth and more
          <span className="networth-chev">
            <ChevronDown size={14} />
          </span>
        </div>
      </div>
      <div className="home-sheet">
        <div className="shortcuts">
          <Shortcut img="home-security" label={"Security\nHub"} onClick={() => soon("Security Hub")} />
          <Shortcut img="home-paynow" label="PayNow" testId="home-paynow" onClick={() => void dispatch({ kind: "payNow" })} />
          <Shortcut img="home-bills" label={"Bills, Cards\n& GIRO"} onClick={() => soon("Bills, Cards & GIRO")} />
          <Shortcut img="home-overseas" label={"Overseas\ntransfer"} onClick={() => void dispatch({ kind: "overseas" })} />
          <Shortcut img="pay-scan" label="Scan & Pay" testId="home-scan" onClick={() => void dispatch({ kind: "scanAndPay" })} />
        </div>

        <div className="section-head">
          <div>
            <h2>Your accounts</h2>
            {acc.failed && minutes != null && (
              <div className="stale" data-testid="stale">
                <Warning /> Updated {minutes} min ago
              </div>
            )}
          </div>
          <span className="section-tools">
            <button aria-label={hide ? "Show balances" : "Hide balances"} onClick={toggleHide} data-testid="eye" aria-pressed={hide}>
              <Eye off={hide} />
            </button>
            <Gear />
          </span>
        </div>

        <div className="card deposits">
          <div className="card-title">Deposits</div>
          <div className="card-right">
            <div className="card-muted">Available balance</div>
            <div className="card-value" data-testid="balance">
              {acc.summary ? (hide ? dots : `SGD ${formatMoney(totalAvailable(acc.summary))}`) : acc.failed ? "–" : <span className="skel skel-value" />}
            </div>
          </div>
          {showAll && acc.summary && (
            <div className="account-list">
              {acc.summary.accounts.map((a) => (
                <div className="account-row" key={a.id}>
                  <div>
                    <div className="account-name">{a.name}</div>
                    <div className="card-muted">{a.numberMasked}</div>
                  </div>
                  <div className="account-bal">{hide ? dots : `${a.currency} ${a.balance}`}</div>
                </div>
              ))}
            </div>
          )}
        </div>
        {acc.failed && !acc.summary && (
          <button className="retry" onClick={() => void refreshAccounts({ interactive: true })}>
            Couldn't load your accounts. Retry
          </button>
        )}
        <div className="card-pair">
          <div className="card small">
            <div className="card-title">Wallet</div>
            <div className="card-right card-right-low">
              <div className="card-muted">Link a wallet to see it here</div>
            </div>
          </div>
          <div className="card small">
            <div className="card-title">Wealth</div>
            <div className="card-right card-right-low">
              <div className="card-muted">Your net worth</div>
              <div className="card-dots">{dots}</div>
            </div>
          </div>
        </div>
        <button className="show-all" onClick={() => setShowAll((v) => !v)} data-testid="show-all">
          <span className="plus-dot">
            <Plus size={16} />
          </span>
          {showAll ? "Hide accounts" : "Show all accounts"}
        </button>

        <h2 className="discover">Discover more</h2>
        <div className="discover-row">
          <div className="discover-card">Keep your account safe</div>
          <div className="discover-card">Insights</div>
        </div>
        <div className="tabbar-space" />
      </div>
    </div>
  );
}

function TopBar({ title }: { title?: string }) {
  return (
    <div className="topbar">
      <span className="icon-badge">
        <Bell size={28} />
        <span className="badge badge-red">45</span>
      </span>
      {title && <span className="topbar-title">{title}</span>}
      <Chat size={28} />
    </div>
  );
}

const PAY_GRID: { img: string; label: string; badge?: string; run: () => void; testId?: string }[] = [
  { img: "pay-paynow", label: "PayNow", run: () => void dispatch({ kind: "payNow" }), testId: "pay-paynow" },
  { img: "pay-local", label: "Local\ntransfer", run: () => soon("Local transfer") },
  { img: "pay-scan", label: "Scan & Pay", run: () => void dispatch({ kind: "scanAndPay" }), testId: "pay-scan" },
  { img: "pay-overseas", label: "Overseas\ntransfer", run: () => void dispatch({ kind: "overseas" }) },
  { img: "pay-bills", label: "Bills, Cards\n& GIRO", run: () => soon("Bills, Cards & GIRO") },
  { img: "pay-scheduled", label: "Scheduled\ntransfer", run: () => soon("Scheduled transfer") },
  { img: "pay-edp", label: "EDP", badge: "New", run: () => soon("EDP") },
  { img: "pay-fx", label: "Exchange\ncurrency", run: () => soon("Exchange currency") },
];

function PayTransfer() {
  const [seg, setSeg] = useState(0);
  return (
    <div className="scroll pay">
      <TopBar />
      <div className="pay-grid-wrap">
        <div className="pay-grid">
          {PAY_GRID.map((g) => (
            <button key={g.img} className="pay-tile" onClick={g.run} data-testid={g.testId}>
              <span className="pay-icon">
                <img src={asset(`img/${g.img}.png`)} alt="" />
                {g.badge && <span className="new-badge">{g.badge}</span>}
              </span>
              <span>{g.label}</span>
            </button>
          ))}
        </div>
        <span className="expand-chev">
          <ChevronDown size={18} />
        </span>
      </div>
      <div className="recipients">
        <div className="recipients-head">
          <h2>Your Recipients &amp; Billers</h2>
          <span className="search-circle">
            <Search size={22} />
          </span>
        </div>
        <div className="seg seg-blue seg-three">
          {[
            ["Recent", 2],
            ["All", 8],
            ["Favourites", 0],
          ].map(([l, n], i) => (
            <button key={l} className={`seg-item ${seg === i ? "seg-on" : ""}`} onClick={() => setSeg(i)}>
              {l} <span className="count">{n}</span>
            </button>
          ))}
        </div>
        <div className="add-recipient">
          <span className="add-circle">
            <Plus size={24} />
          </span>
          Add a recipient or bill
        </div>
        <div className="recent-label">Recent transfers</div>
        <Recipient initials="KC" tone="green" name="KOPI CORNER PTE. LTD." sub="UEN •••••345K" />
        <Recipient initials="TN" tone="blue" name="TAN ** **NG" sub="MOBILE, +65 •••• 4567" />
      </div>
      <div className="tabbar-space" />
    </div>
  );
}

function Recipient({ initials, name, sub, tone }: { initials: string; name: string; sub: string; tone: "green" | "blue" }) {
  return (
    <div className="recipient">
      <span className={`avatar avatar-${tone}`}>{initials}</span>
      <span className="recipient-text">
        <span className="recipient-name">{name}</span>
        <span className="recipient-sub">{sub}</span>
      </span>
      <span className="paynow-tag">PAYNOW</span>
    </div>
  );
}

function Wealth() {
  const [hide, toggleHide] = useHideBalance();
  return (
    <div className="scroll plain-tab">
      <TopBar title="Wealth" />
      <div className="pad">
        <div className="card wealth-card">
          <div className="card-muted">Your net worth</div>
          <div className="wealth-value">{hide ? "SGD ••••••" : "SGD 12,465.67"}</div>
          <button className="link-btn" onClick={toggleHide}>
            {hide ? "Show" : "Hide"} amounts
          </button>
        </div>
        <List
          title="Grow your wealth"
          items={[
            ["Managed Portfolio", "Automated investing from SGD 100"],
            ["Unit Trusts", "Funds picked by our experts"],
            ["Insurance", "Protect what matters"],
          ]}
        />
      </div>
      <div className="tabbar-space" />
    </div>
  );
}

function List({ title, items, accent }: { title: string; items: [string, string][]; accent?: ReactNode }) {
  return (
    <div className="card list-card">
      <div className="list-head">
        <span className="list-title">{title}</span>
        {accent}
      </div>
      {items.map(([t, s]) => (
        <button key={t} className="list-item" onClick={() => void dispatch({ kind: "apply" })}>
          <span className="list-item-title">{t}</span>
          <span className="list-item-sub">{s}</span>
        </button>
      ))}
      <div className="view-all">
        View all <ChevronRight size={14} />
      </div>
    </div>
  );
}

function Apply() {
  return (
    <div className="scroll plain-tab">
      <TopBar title="Apply" />
      <div className="pad">
        <h2 className="apply-h">Discover more with us</h2>
        <div className="apply-sub">Explore a category</div>
        <List
          title="Bank"
          accent={<span className="accent accent-bank" />}
          items={[
            ["Deposits", "Start saving with us"],
            ["Fixed Deposits", "Maximise your savings"],
            ["Supplementary Retirement Scheme", "Enjoy tax savings"],
          ]}
        />
        <List
          title="Cards"
          accent={<span className="accent accent-cards" />}
          items={[
            ["Credit Cards", "For rebates, miles, rewards"],
            ["Debit Cards", "For everyday banking"],
            ["Card Services", "Payment plans and more"],
          ]}
        />
      </div>
      <div className="tabbar-space" />
    </div>
  );
}

const QUICK = ["eDocuments", "Replace/Block Card", "Personalise Your App", "Rewards", "Update Particulars", "Lock Your Account"];

function More() {
  return (
    <div className="scroll more">
      <div className="topbar more-top">
        <span className="icon-badge">
          <Bell size={28} />
          <span className="badge badge-red">51</span>
        </span>
        <span className="more-search">
          <Search size={18} /> Search ‘more’
        </span>
        <Chat size={28} />
      </div>
      <div className="profile">
        <span className="profile-avatar" />
        <div>
          <div className="profile-name">ALEX TAN</div>
          <button className="logout-solid" onClick={signOut}>
            LOG OUT
          </button>
        </div>
      </div>
      <button className="hub" onClick={() => soon("Security Hub")}>
        <span className="hub-icon">
          <img src={asset("img/home-security.png")} alt="" />
        </span>
        <span>
          <span className="hub-kicker">SECURITY HUB</span>
          <span className="hub-title">Security settings and tips</span>
        </span>
        <ChevronRight size={18} />
      </button>
      <div className="more-heading">QUICK ACCESS</div>
      <div className="quick-grid">
        {QUICK.map((q) => (
          <button key={q} className="quick" onClick={() => soon(q)}>
            <span className="quick-icon" />
            <span>{q}</span>
          </button>
        ))}
      </div>
      <div className="more-heading">ABOUT THIS DEMO</div>
      <div className="about-card" data-testid="about-demo">
        {DEMO && <p>{PRIVACY_NOTE}</p>}
        {DEMO && <p data-testid="timing-note">{TIMING_NOTE}</p>}
        <p>Recent payees and the demo account live in this browser&rsquo;s storage. Reset clears them.</p>
        <button className="about-reset" onClick={resetDemo} data-testid="reset-demo">
          Reset demo
        </button>
      </div>
      <div className="tabbar-space" />
    </div>
  );
}
