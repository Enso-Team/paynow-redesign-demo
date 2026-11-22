import type { SVGProps } from "react";

type P = SVGProps<SVGSVGElement> & { size?: number };

const line = (size: number, props: P) => ({
  width: size,
  height: size,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.5,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
  ...props,
});

export const Bell = ({ size = 28, ...p }: P) => (
  <svg {...line(size, p)}>
    <path d="M6 16.5V11a6 6 0 1 1 12 0v5.5l1.5 1.5h-15L6 16.5Z" />
    <path d="M10 20.5a2 2 0 0 0 4 0" />
    <path d="M12 3.2V5" />
  </svg>
);

export const Chat = ({ size = 28, ...p }: P) => (
  <svg {...line(size, p)}>
    <path d="M4 5.5h16v11H9.5L6 19.5v-3H4v-11Z" />
    <path d="M8.5 11c1.8 1.8 5.2 1.8 7 0" />
  </svg>
);

export const Close = ({ size = 24, ...p }: P) => (
  <svg {...line(size, { strokeWidth: 1.4, ...p })}>
    <path d="M5 5l14 14M19 5L5 19" />
  </svg>
);

export const Info = ({ size = 26, ...p }: P) => (
  <svg {...line(size, { strokeWidth: 1.2, ...p })}>
    <circle cx="12" cy="12" r="10" />
    <path d="M12 10.5v6.5M10.8 17h2.6M10.8 10.5H12" />
    <circle cx="12" cy="7.3" r=".6" fill="currentColor" />
  </svg>
);

export const ChevronRight = ({ size = 18, ...p }: P) => (
  <svg {...line(size, p)}>
    <path d="M9 5l7 7-7 7" />
  </svg>
);

export const ChevronDown = ({ size = 18, ...p }: P) => (
  <svg {...line(size, p)}>
    <path d="M5 9l7 7 7-7" />
  </svg>
);

export const Eye = ({ size = 26, off = false, ...p }: P & { off?: boolean }) => (
  <svg {...line(size, p)}>
    <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z" />
    <circle cx="12" cy="12" r="3.2" />
    {off && <path d="M4 20 20 4" />}
  </svg>
);

export const Gear = ({ size = 26, ...p }: P) => (
  <svg {...line(size, p)}>
    <circle cx="12" cy="12" r="3" />
    <path d="M12 2.8l1.6 2.1 2.6-.6.6 2.6 2.4 1.2-1 2.4 1 2.4-2.4 1.2-.6 2.6-2.6-.6L12 21.2l-1.6-2.1-2.6.6-.6-2.6-2.4-1.2 1-2.4-1-2.4 2.4-1.2.6-2.6 2.6.6L12 2.8Z" />
  </svg>
);

export const Plus = ({ size = 22, ...p }: P) => (
  <svg {...line(size, p)}>
    <path d="M12 5v14M5 12h14" />
  </svg>
);

export const Search = ({ size = 22, ...p }: P) => (
  <svg {...line(size, p)}>
    <circle cx="11" cy="11" r="7" />
    <path d="M16.5 16.5 21 21" />
  </svg>
);

export const Mobile = ({ size = 26, ...p }: P) => (
  <svg {...line(size, { strokeWidth: 1.2, ...p })}>
    <rect x="7" y="2.5" width="10" height="19" rx="2" />
    <circle cx="12" cy="18.2" r=".5" fill="currentColor" />
  </svg>
);

export const IdCard = ({ size = 26, ...p }: P) => (
  <svg {...line(size, { strokeWidth: 1.2, ...p })}>
    <rect x="2.5" y="5" width="19" height="14" rx="1.5" />
    <circle cx="8.5" cy="10.5" r="2" />
    <path d="M5.5 16c.6-2 5.4-2 6 0M14 10h4.5M14 13h3" />
  </svg>
);

export const Shop = ({ size = 26, ...p }: P) => (
  <svg {...line(size, { strokeWidth: 1.2, ...p })}>
    <path d="M3.5 9.5 5 4.5h14l1.5 5" />
    <path d="M3.5 9.5c0 1.4 1.3 2.3 2.9 2.3s2.8-.9 2.8-2.3c0 1.4 1.3 2.3 2.8 2.3s2.8-.9 2.8-2.3c0 1.4 1.3 2.3 2.8 2.3s2.9-.9 2.9-2.3" />
    <path d="M5 12v8h14v-8M10 20v-4.5h4V20" />
  </svg>
);

export const Mail = ({ size = 26, ...p }: P) => (
  <svg {...line(size, { strokeWidth: 1.2, ...p })}>
    <rect x="3" y="7" width="18" height="13" rx="1.5" />
    <path d="M3 9.5 12 14l9-4.5M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7" />
  </svg>
);

export const Globe = ({ size = 26, ...p }: P) => (
  <svg {...line(size, { strokeWidth: 1.2, ...p })}>
    <circle cx="12" cy="12" r="9.5" />
    <path d="M2.5 12h19M12 2.5c3 3 3 16 0 19M12 2.5c-3 3-3 16 0 19" />
  </svg>
);

export const QrScan = ({ size = 26, ...p }: P) => (
  <svg {...line(size, { strokeWidth: 1.2, ...p })}>
    <path d="M3 8V4.5A1.5 1.5 0 0 1 4.5 3H8M16 3h3.5A1.5 1.5 0 0 1 21 4.5V8M21 16v3.5a1.5 1.5 0 0 1-1.5 1.5H16M8 21H4.5A1.5 1.5 0 0 1 3 19.5V16" />
    <rect x="7" y="7" width="4" height="4" rx=".6" />
    <rect x="13" y="7" width="4" height="4" rx=".6" />
    <rect x="7" y="13" width="4" height="4" rx=".6" />
    <path d="M13 13h1.5M16.5 13H17v1.5M13 16.5V17h4" />
  </svg>
);

export const Back = ({ size = 26, ...p }: P) => (
  <svg {...line(size, { strokeWidth: 1.6, ...p })}>
    <path d="M15 4 7 12l8 8" />
  </svg>
);

export const Warning = ({ size = 14, ...p }: P) => (
  <svg {...line(size, { strokeWidth: 1.8, ...p })}>
    <path d="M12 3 2 20h20L12 3Z" />
    <path d="M12 10v4.5M12 17.2v.2" />
  </svg>
);

export const FaceGlyph = ({ size = 84, ...p }: P) => (
  <svg width={size} height={size} viewBox="0 0 100 100" fill="none" stroke="currentColor" strokeWidth={5} strokeLinecap="round" strokeLinejoin="round" aria-hidden {...p}>
    <path className="fg-corner" d="M10 30V18a8 8 0 0 1 8-8h12" />
    <path className="fg-corner" d="M70 10h12a8 8 0 0 1 8 8v12" />
    <path className="fg-corner" d="M90 70v12a8 8 0 0 1-8 8H70" />
    <path className="fg-corner" d="M30 90H18a8 8 0 0 1-8-8V70" />
    <g className="fg-face">
      <path d="M33 36v7M67 36v7M50 38v18h-5" />
      <path d="M35 66c8 7 22 7 30 0" />
    </g>
    <path className="fg-check" d="M28 52l15 15 29-32" />
  </svg>
);
