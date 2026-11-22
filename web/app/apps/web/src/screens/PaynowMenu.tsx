import type { ReactNode } from "react";
import { dispatch, openMenuForm } from "../lib/router";
import { go, type Screen } from "../lib/store";
import { clearRecentPayees, useRecentPayees, type RecentPayee } from "../lib/recent";
import { maskProxy } from "paynow-form/src/money";
import { ChevronRight, Close, Globe, IdCard, Mail, Mobile, QrScan, Shop } from "../icons";

function Row({ icon, label, onClick, testId }: { icon: ReactNode; label: string; onClick: () => void; testId?: string }) {
  return (
    <button className="menu-row" onClick={onClick} data-testid={testId}>
      <span className="menu-icon">{icon}</span>
      <span className="menu-label">{label}</span>
      <ChevronRight size={20} className="menu-chev" />
    </button>
  );
}

/** Payees paid from this device, one tap from a filled form. They live only in this browser. */
function RecentPayees({ here }: { here: Screen }) {
  const recent = useRecentPayees();
  if (!recent.length) return null;
  const open = (p: RecentPayee) =>
    go({ name: "form", init: { proxyType: p.proxyType, proxyValue: p.proxyValue, amountEditable: true, source: "menu" }, back: here });
  return (
    <>
      <div className="menu-section" data-testid="recent-payees">
        <div className="menu-heading menu-heading-row">
          <span>Recent payees</span>
          <button className="menu-clear" onClick={clearRecentPayees} data-testid="recent-clear">
            Clear
          </button>
        </div>
        {recent.map((p) => (
          <button
            key={`${p.proxyType}:${p.proxyValue}`}
            className="menu-row recent-row"
            onClick={() => open(p)}
            data-testid={`recent-${p.proxyValue}`}
          >
            <span className="menu-icon">{p.proxyType === "MOBILE" ? <Mobile /> : <Shop />}</span>
            <span className="menu-label recent-text">
              <span className="recent-name">{p.maskedName}</span>
              <span className="recent-sub">{maskProxy(p.proxyType, p.proxyValue)}</span>
            </span>
            <ChevronRight size={20} className="menu-chev" />
          </button>
        ))}
      </div>
      <div className="menu-gap" />
    </>
  );
}

export function PaynowMenu({ back }: { back: Screen }) {
  const here: Screen = { name: "paynowMenu", back };
  const soon = (title: string) => () => go({ name: "placeholder", title, back: here });
  return (
    <div className="plain paynow-menu">
      <header className="navbar">
        <h1>PayNow</h1>
        <button className="navbar-right" aria-label="Close" onClick={() => go(back)} data-testid="menu-close">
          <Close size={26} />
        </button>
      </header>
      <div className="seg seg-blue seg-two">
        <span className="seg-item seg-on">Transfer</span>
        <span className="seg-item">Recipients</span>
      </div>
      <div className="menu-scroll">
        <div className="grey-pad">
          <div className="banner">
            <span className="banner-i">i</span>
            <span>
              Link your mobile number to <u>PayNow</u> to get paid by anyone in Singapore
            </span>
          </div>
        </div>
        <RecentPayees here={here} />
        <div className="menu-section">
          <div className="menu-heading">Local transfer</div>
          <Row
            icon={<QrScan />}
            label="Scan a QR"
            testId="menu-scan"
            onClick={() => void dispatch({ kind: "scanAndPay" })}
          />
          <Row icon={<Mobile />} label="PayNow to mobile" testId="menu-mobile" onClick={() => openMenuForm("MOBILE")} />
          <Row icon={<IdCard />} label="PayNow to NRIC" onClick={soon("PayNow to NRIC")} />
          <Row icon={<Shop />} label="PayNow to UEN" testId="menu-uen" onClick={() => openMenuForm("UEN")} />
          <Row icon={<Mail />} label="PayNow to VPA" onClick={soon("PayNow to VPA")} />
        </div>
        <div className="menu-gap" />
        <div className="menu-section">
          <div className="menu-heading">Overseas transfer</div>
          <Row icon={<Globe />} label="DuitNow (Malaysia)" onClick={soon("DuitNow (Malaysia)")} />
          <Row icon={<Globe />} label="PromptPay (Thailand)" onClick={soon("PromptPay (Thailand)")} />
          <Row icon={<Globe />} label="UPI (India)" onClick={soon("UPI (India)")} />
        </div>
      </div>
    </div>
  );
}
