export type ProxyType = "MOBILE" | "UEN";
export type Service = "account" | "lookup" | "payment";

export interface PaynowInit {
  proxyType?: ProxyType;
  proxyValue?: string;
  amount?: string;
  amountEditable: boolean;
  reference?: string;
  source: "qr" | "menu";
}

export interface ApiInit {
  method?: string;
  body?: unknown;
  headers?: Record<string, string>;
}

export interface ApiResponse {
  status: number;
  body: unknown;
}

export interface PaynowResult {
  paymentId: string;
  status: "SETTLED" | "REJECTED";
  amount: string;
  maskedName: string;
}

export interface PickedContact {
  name: string;
  phone: string;
}

export interface PaynowHost {
  api(service: Service, path: string, init?: ApiInit): Promise<ApiResponse>;
  done(result: PaynowResult): void;
  close(): void;
  /** Opens the address book and resolves with the picked contact, or null when cancelled. Hosts without one leave it out. */
  pickContact?(): Promise<PickedContact | null>;
}

export interface PaynowFormApi {
  open(init: PaynowInit): void;
}

declare global {
  interface Window {
    paynowHost?: PaynowHost;
    __PAYNOW_INIT__?: PaynowInit;
    paynowForm?: PaynowFormApi;
  }
}

export function host(): PaynowHost {
  const h = window.paynowHost;
  if (!h) throw new Error("window.paynowHost is not set");
  return h;
}
