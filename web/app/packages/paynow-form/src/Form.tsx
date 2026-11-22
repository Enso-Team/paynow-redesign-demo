import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { isValidProxy, normalizeMobile } from "sgqr";
import { host, type PaynowInit, type PaynowResult, type ProxyType } from "./bridge";
import { contactMobile } from "./contact";
import { display, fromCents, initials, isAmountInput, maskProxy, toCents, uuid } from "./money";

interface Account {
  id: string;
  name: string;
  numberMasked: string;
  balance: string;
  available: string;
  currency: string;
}

interface Summary {
  displayName: string;
  accounts: Account[];
  paynowDailyLimit: string;
  paynowUsedToday: string;
}

type AccountState = { kind: "loading" } | { kind: "error" } | { kind: "ready"; summary: Summary };

type LookupState =
  | { kind: "idle" }
  | { kind: "pending" }
  | { kind: "found"; maskedName: string; bankCode: string }
  | { kind: "notFound" }
  | { kind: "timeout" }
  | { kind: "rateLimited" }
  | { kind: "error" };

type PayState =
  | { kind: "idle" }
  | { kind: "submitting" }
  | { kind: "failed"; message: string; retry: boolean }
  | { kind: "rejected"; result: PaynowResult };

const MAX_REF = 25;
const POLLS = 12;

function errorCode(body: unknown): string | undefined {
  if (body && typeof body === "object" && "code" in body) return String((body as { code: unknown }).code);
  return undefined;
}

const PAY_ERRORS: Record<string, string> = {
  INSUFFICIENT_FUNDS: "Not enough in this account",
  LIMIT_EXCEEDED: "Over your PayNow daily limit",
  PROXY_NOT_FOUND: "No PayNow account for this number",
};

export function Form({ init }: { init: PaynowInit }) {
  const [idempotencyKey] = useState(uuid);
  const proxyType: ProxyType = init.proxyType ?? "MOBILE";
  const fromQr = init.source === "qr";

  const [accountState, setAccountState] = useState<AccountState>({ kind: "loading" });
  const [accountId, setAccountId] = useState<string>("");
  const [accountTick, setAccountTick] = useState(0);

  const [proxyInput, setProxyInput] = useState(init.proxyValue ?? "");
  /** The picked contact's name, shown under the masked name. It stays on this device. */
  const [contact, setContact] = useState<{ name: string; mobile: string } | null>(null);
  const [contactError, setContactError] = useState(false);
  const canPickContact = proxyType === "MOBILE" && typeof window.paynowHost?.pickContact === "function";

  const pickContact = async () => {
    const picked = await host().pickContact?.().catch(() => null);
    if (!picked) return;
    const mobile = contactMobile(picked.phone);
    if (!mobile) {
      setContactError(true);
      return;
    }
    setContactError(false);
    setContact({ name: picked.name, mobile });
    setProxyInput(mobile);
  };
  const [lookup, setLookup] = useState<LookupState>({ kind: "idle" });
  const [lookupTick, setLookupTick] = useState(0);
  const lookupSeq = useRef(0);
  const firstLookup = useRef(true);

  const [amount, setAmount] = useState(init.amount ?? "");
  const [reference, setReference] = useState((init.reference ?? (fromQr ? "" : "PayNow transfer")).slice(0, MAX_REF));
  const [pay, setPay] = useState<PayState>({ kind: "idle" });
  const busy = useRef(false);
  const amountEditable = init.amountEditable || !init.amount;

  const proxyValue = proxyType === "MOBILE" ? normalizeMobile(proxyInput) : proxyInput.trim().toUpperCase();
  const proxyValid = isValidProxy(proxyType, proxyValue);

  useEffect(() => {
    let live = true;
    setAccountState({ kind: "loading" });
    host()
      .api("account", "/accounts/summary")
      .then((r) => {
        if (!live) return;
        if (r.status === 200) {
          const summary = r.body as Summary;
          setAccountState({ kind: "ready", summary });
          setAccountId((id) => id || summary.accounts[0]?.id || "");
        } else setAccountState({ kind: "error" });
      })
      .catch(() => live && setAccountState({ kind: "error" }));
    return () => {
      live = false;
    };
  }, [accountTick]);

  useEffect(() => {
    if (!proxyValid) {
      lookupSeq.current++;
      setLookup({ kind: "idle" });
      return;
    }
    const seq = ++lookupSeq.current;
    setLookup({ kind: "pending" });
    const delay = fromQr && firstLookup.current ? 0 : 300;
    firstLookup.current = false;
    const timer = setTimeout(() => {
      const q = `/paynow/lookup?type=${proxyType}&value=${encodeURIComponent(proxyValue)}`;
      host()
        .api("lookup", q)
        .then((r) => {
          if (seq !== lookupSeq.current) return;
          const body = r.body as { maskedName?: string; bankCode?: string };
          if (r.status === 200 && body?.maskedName) {
            setLookup({ kind: "found", maskedName: body.maskedName, bankCode: body.bankCode ?? "" });
          } else if (r.status === 404 || errorCode(r.body) === "PROXY_NOT_FOUND") setLookup({ kind: "notFound" });
          else if (r.status === 504 || errorCode(r.body) === "DIRECTORY_TIMEOUT") setLookup({ kind: "timeout" });
          else if (r.status === 429) setLookup({ kind: "rateLimited" });
          else setLookup({ kind: "error" });
        })
        .catch(() => seq === lookupSeq.current && setLookup({ kind: "error" }));
    }, delay);
    return () => clearTimeout(timer);
  }, [proxyType, proxyValue, proxyValid, lookupTick, fromQr]);

  const summary = accountState.kind === "ready" ? accountState.summary : null;
  const account = summary?.accounts.find((a) => a.id === accountId) ?? summary?.accounts[0];
  const amountCents = toCents(amount);
  const availableCents = toCents(account?.available) ?? 0;
  const limitLeftCents = summary
    ? Math.max(0, (toCents(summary.paynowDailyLimit) ?? 0) - (toCents(summary.paynowUsedToday) ?? 0))
    : null;

  const amountError = useMemo(() => {
    if (amountCents == null || amountCents === 0 || !account) return null;
    if (amountCents > availableCents) return "Not enough in this account";
    if (limitLeftCents != null && amountCents > limitLeftCents) return "Over your PayNow daily limit";
    return null;
  }, [amountCents, availableCents, limitLeftCents, account]);

  const locked = pay.kind === "submitting";
  const canPay =
    lookup.kind === "found" && !!account && amountCents != null && amountCents > 0 && !amountError && !locked;

  const runPay = useCallback(async () => {
    if (!canPay || busy.current || lookup.kind !== "found" || !account || amountCents == null) return;
    busy.current = true;
    setPay({ kind: "submitting" });
    const amountText = fromCents(amountCents);
    const maskedName = lookup.maskedName;
    try {
      const r = await host().api("payment", "/payments/paynow", {
        method: "POST",
        headers: { "Idempotency-Key": idempotencyKey },
        body: {
          fromAccountId: account.id,
          proxyType,
          proxyValue,
          amount: amountText,
          currency: "SGD",
          reference,
        },
      });
      if (r.status < 200 || r.status >= 300) {
        const code = errorCode(r.body);
        const known = code ? PAY_ERRORS[code] : undefined;
        setPay({ kind: "failed", message: known ?? "Something went wrong. Try again.", retry: !known });
        return;
      }
      const paymentId = String((r.body as { paymentId: string }).paymentId);
      for (let i = 0; i < POLLS; i++) {
        const p = await host().api("payment", `/payments/${encodeURIComponent(paymentId)}?waitMs=5000`);
        if (p.status !== 200) {
          setPay({ kind: "failed", message: "We couldn't confirm this payment. Try again.", retry: true });
          return;
        }
        const b = p.body as { status: string; amount?: string; maskedName?: string };
        if (b.status === "SETTLED" || b.status === "REJECTED") {
          const result: PaynowResult = {
            paymentId,
            status: b.status,
            amount: b.amount ?? amountText,
            maskedName: b.maskedName ?? maskedName,
          };
          if (b.status === "SETTLED") host().done(result);
          else setPay({ kind: "rejected", result });
          return;
        }
      }
      setPay({ kind: "failed", message: "This is taking longer than usual. Try again.", retry: true });
    } catch {
      setPay({ kind: "failed", message: "Something went wrong. Try again.", retry: true });
    } finally {
      busy.current = false;
    }
  }, [canPay, lookup, account, amountCents, idempotencyKey, proxyType, proxyValue, reference]);

  if (pay.kind === "rejected") {
    return (
      <div className="pf">
        <Header />
        <div className="pf-result">
          <div className="pf-result-icon" aria-hidden>
            <svg viewBox="0 0 64 64" width="64" height="64">
              <circle cx="32" cy="32" r="32" fill="#e1251b" />
              <path d="M22 22l20 20M42 22L22 42" stroke="#fff" strokeWidth="5" strokeLinecap="round" />
            </svg>
          </div>
          <p className="pf-result-title" data-testid="rejected">
            Payment didn't go through. No money left your account.
          </p>
          <p className="pf-result-sub">
            SGD {display(toCents(pay.result.amount) ?? 0)} to {pay.result.maskedName}
          </p>
        </div>
        <div className="pf-footer">
          <button className="pf-btn" onClick={() => host().done(pay.result)}>
            Done
          </button>
        </div>
      </div>
    );
  }

  const recipientName = lookup.kind === "found" ? lookup.maskedName : "";

  return (
    <div className="pf">
      <Header />
      <div className="pf-scroll">
        <section className="pf-from">
          <div className="pf-avatar pf-avatar-bank" aria-hidden>
            <BankMark />
          </div>
          {accountState.kind === "ready" && account ? (
            <div className="pf-row-text">
              <div className="pf-title">{account.name}</div>
              <div className="pf-sub pf-sub-split">
                <span>{account.numberMasked}</span>
                <span data-testid="available">SGD {display(availableCents)}</span>
              </div>
              {summary && summary.accounts.length > 1 && (
                <select
                  className="pf-account-select"
                  aria-label="Pay from"
                  value={account.id}
                  disabled={locked}
                  onChange={(e) => setAccountId(e.target.value)}
                >
                  {summary.accounts.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name} {a.numberMasked}
                    </option>
                  ))}
                </select>
              )}
            </div>
          ) : accountState.kind === "error" ? (
            <div className="pf-row-text">
              <div className="pf-title">Couldn't load your accounts</div>
              <button className="pf-link" onClick={() => setAccountTick((t) => t + 1)}>
                Retry
              </button>
            </div>
          ) : (
            <div className="pf-row-text">
              <div className="pf-skel pf-skel-title" />
              <div className="pf-skel pf-skel-sub" />
            </div>
          )}
          <div className="pf-chevrons" aria-hidden>
            <svg viewBox="0 0 12 14" width="12" height="14">
              <path d="M2 2l4 4 4-4M2 8l4 4 4-4" fill="none" stroke="#b9c0c5" strokeWidth="1.4" />
            </svg>
          </div>
        </section>

        {!fromQr && (
          <section className="pf-proxy">
            <label className="pf-label" htmlFor="pf-proxy">
              {proxyType === "MOBILE" ? "Mobile number" : "UEN"}
            </label>
            <div className="pf-input-wrap">
              {proxyType === "MOBILE" && <span className="pf-prefix">+65</span>}
              <input
                id="pf-proxy"
                className="pf-input"
                aria-label={proxyType === "MOBILE" ? "Mobile number" : "UEN"}
                data-testid="proxy-input"
                inputMode={proxyType === "MOBILE" ? "numeric" : "text"}
                autoComplete="off"
                autoCapitalize="characters"
                placeholder={proxyType === "MOBILE" ? "8 digits" : "e.g. 201912345K"}
                maxLength={proxyType === "MOBILE" ? 12 : 10}
                value={proxyInput}
                disabled={locked}
                autoFocus
                onChange={(e) => {
                  setContactError(false);
                  setProxyInput(e.target.value);
                }}
              />
              {canPickContact && (
                <button
                  id="pf-contacts"
                  type="button"
                  className="pf-contacts"
                  aria-label="Choose from contacts"
                  disabled={locked}
                  onClick={() => void pickContact()}
                >
                  <ContactsIcon />
                </button>
              )}
            </div>
            {contactError && (
              <div className="pf-field-error" role="alert" data-testid="contact-error">
                Pick a Singapore mobile number
              </div>
            )}
          </section>
        )}

        {(fromQr || lookup.kind !== "idle") && (
          <section className="pf-to" data-testid="recipient" data-state={lookup.kind}>
            <RecipientRow
              lookup={lookup}
              proxyType={proxyType}
              proxyValue={proxyValue}
              contactName={contact && contact.mobile === proxyValue ? contact.name : null}
              onRetry={() => setLookupTick((t) => t + 1)}
            />
          </section>
        )}

        <section className="pf-send">
          <div>
            <div className="pf-send-label">You send</div>
            <div className="pf-send-ccy">SGD</div>
          </div>
          <input
            id="pf-amount"
            className="pf-amount"
            data-testid="amount"
            aria-label="Amount in SGD"
            inputMode="decimal"
            placeholder="0.00"
            value={amount}
            readOnly={!amountEditable}
            disabled={locked}
            onChange={(e) => isAmountInput(e.target.value) && setAmount(e.target.value)}
            onBlur={() => amountCents != null && amountCents > 0 && setAmount(fromCents(amountCents))}
          />
        </section>
        {amountError && (
          <div className="pf-amount-error" role="alert" data-testid="amount-error">
            {amountError}
          </div>
        )}
        <section className="pf-limit">
          <div>
            <div className="pf-limit-label">
              Daily limit left <InfoCircle />
            </div>
            <div className="pf-limit-value" data-testid="limit-left">
              {limitLeftCents == null ? "SGD –" : `SGD ${display(limitLeftCents)}`}
            </div>
          </div>
          <div className="pf-limit-change">
            Change limit <span aria-hidden>›</span>
          </div>
        </section>

        <section className="pf-comments">
          <label className="pf-label" htmlFor="pf-ref">
            Add comments for recipient (optional)
          </label>
          <input
            id="pf-ref"
            className="pf-input pf-input-box"
            aria-label="Comments for recipient"
            maxLength={MAX_REF}
            value={reference}
            disabled={locked}
            onChange={(e) => setReference(e.target.value.slice(0, MAX_REF))}
          />
          <div className="pf-counter">
            {reference.length}/{MAX_REF}
          </div>
        </section>

        <div className="pf-banner">
          <span className="pf-banner-i" aria-hidden>
            i
          </span>
          <span>
            Link your mobile number to <u>PayNow</u> to get paid by anyone in Singapore
          </span>
        </div>
      </div>

      <div className="pf-footer">
        {pay.kind === "failed" && (
          <div className="pf-pay-error" role="alert" data-testid="pay-error">
            {pay.message}
          </div>
        )}
        <button
          id="pf-pay"
          className="pf-btn"
          data-testid="pay"
          disabled={!canPay}
          aria-busy={locked}
          onClick={runPay}
        >
          {locked ? <span className="pf-spinner" aria-label="Paying" /> : pay.kind === "failed" && pay.retry ? "Try again" : "Pay"}
        </button>
      </div>
      {recipientName && <span hidden data-testid="masked-name">{recipientName}</span>}
    </div>
  );
}

function RecipientRow({
  lookup,
  proxyType,
  proxyValue,
  contactName,
  onRetry,
}: {
  lookup: LookupState;
  proxyType: ProxyType;
  proxyValue: string;
  contactName: string | null;
  onRetry: () => void;
}) {
  const sub = proxyValue ? maskProxy(proxyType, proxyValue) : "";
  switch (lookup.kind) {
    case "found":
      return (
        <>
          <div className="pf-avatar pf-avatar-initials">{initials(lookup.maskedName)}</div>
          <div className="pf-row-text">
            <div className="pf-title" data-testid="name">
              {lookup.maskedName}
            </div>
            <div className="pf-sub">{sub}</div>
            {contactName && (
              <div className="pf-sub pf-contact" data-testid="contact-name">
                From contacts: {contactName}
              </div>
            )}
          </div>
          <span className="pf-tag">PAYNOW</span>
        </>
      );
    case "notFound":
      return (
        <div className="pf-row-text pf-row-msg">
          <div className="pf-msg pf-msg-error" data-testid="lookup-error">
            No PayNow account for this number
          </div>
          <div className="pf-sub">{sub}</div>
        </div>
      );
    case "timeout":
    case "error":
    case "rateLimited":
      return (
        <div className="pf-row-text pf-row-msg">
          <div className="pf-msg pf-msg-error" data-testid="lookup-error">
            {lookup.kind === "rateLimited" ? "Too many checks. Wait a minute and retry." : "Couldn't check the name"}
          </div>
          <div className="pf-sub">{sub}</div>
          <button className="pf-link" onClick={onRetry} data-testid="lookup-retry">
            Retry
          </button>
        </div>
      );
    default:
      return (
        <>
          <div className="pf-avatar pf-skel-circle" />
          <div className="pf-row-text" aria-busy>
            <div className="pf-skel pf-skel-title" data-testid="name-skeleton" />
            <div className="pf-sub">{sub}</div>
          </div>
        </>
      );
  }
}

/** The address-book glyph: a card with a person and index tabs. */
function ContactsIcon() {
  return (
    <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden>
      <rect x="4.5" y="3" width="14" height="18" rx="2" fill="none" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="11.5" cy="10" r="2.6" fill="none" stroke="currentColor" strokeWidth="1.5" />
      <path d="M7.4 17c.6-2.2 2.2-3.3 4.1-3.3s3.5 1.1 4.1 3.3" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M18.5 7h1.5M18.5 11h1.5M18.5 15h1.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

/**
 * Close acts on pointer down, before the tap can blur a focused field and move the page under the
 * finger as the keyboard goes. The host dismisses the keyboard, then the form. Click covers keyboard users.
 */
function Header() {
  const closed = useRef(false);
  const close = () => {
    if (closed.current) return;
    closed.current = true;
    host().close();
  };
  return (
    <header className="pf-header">
      <h1>PayNow Transfer</h1>
      <button
        id="pf-close"
        className="pf-close"
        aria-label="Close"
        onPointerDown={(e) => {
          e.preventDefault();
          close();
        }}
        onClick={close}
      >
        <svg viewBox="0 0 24 24" width="24" height="24">
          <path d="M5 5l14 14M19 5L5 19" stroke="#4a5257" strokeWidth="1.6" strokeLinecap="round" />
        </svg>
      </button>
    </header>
  );
}

function InfoCircle() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" aria-hidden className="pf-info">
      <circle cx="8" cy="8" r="7" fill="none" stroke="currentColor" strokeWidth="1.1" />
      <path d="M8 7v4.5M8 4.6v.2" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  );
}

function BankMark() {
  return (
    <svg viewBox="0 0 40 40" width="40" height="40">
      <circle cx="20" cy="20" r="20" fill="#2f6fb5" />
      <g fill="#fff">
        <path d="M20 10.5 29 15v1.8H11V15l9-4.5Z" />
        <rect x="13" y="18.5" width="2.4" height="8" />
        <rect x="18.8" y="18.5" width="2.4" height="8" />
        <rect x="24.6" y="18.5" width="2.4" height="8" />
        <rect x="11" y="27.5" width="18" height="2" />
      </g>
    </svg>
  );
}
