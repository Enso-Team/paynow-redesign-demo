import type { PaynowResult } from "paynow-form/src/bridge";
import { go, setState } from "../lib/store";
import { Close } from "../icons";

function money(amount: string) {
  const n = Number(amount);
  return Number.isFinite(n) ? n.toLocaleString("en-SG", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : amount;
}

export function Sent({ result }: { result: PaynowResult }) {
  const home = () => {
    setState({ tab: "home" });
    go({ name: "tabs" });
  };
  const ref = result.paymentId.replace(/[^A-Za-z0-9]/g, "").slice(-7).toUpperCase();
  return (
    <div className="plain sent" data-testid="sent">
      <header className="navbar navbar-flat">
        <h1>PayNow Transfer</h1>
        <button className="navbar-right" aria-label="Close" onClick={home}>
          <Close size={26} />
        </button>
      </header>
      <div className="sent-body">
        <svg className="sent-tick" viewBox="0 0 100 100" width="98" height="98" aria-hidden>
          <circle cx="50" cy="50" r="50" fill="#1da462" />
          <path d="M30 52l13 14 27-34" fill="none" stroke="#fff" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <div className="sent-label">Sent</div>
        <div className="sent-amount" data-testid="sent-amount">
          SGD {money(result.amount)}
        </div>
        <div className="sent-to">to {result.maskedName} · PayNow</div>
        <div className="sent-ref">Reference {ref}</div>
      </div>
      <div className="sent-foot">
        <button className="primary-btn" onClick={home} data-testid="sent-done">
          Done
        </button>
      </div>
    </div>
  );
}
