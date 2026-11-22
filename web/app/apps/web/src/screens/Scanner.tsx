import { useEffect, useRef, useState } from "react";
import jsQR from "jsqr";
import { dispatch, qrToInit } from "../lib/router";
import { go, toast, type Screen } from "../lib/store";
import { Close, Info } from "../icons";
import { asset } from "../lib/demo";

const SAMPLES = [
  { file: "mobile-91234567-12.50", label: "91234567 · SGD 12.50" },
  { file: "uen-201912345K-editable", label: "UEN · any amount" },
  { file: "not-paynow-nets", label: "NETS (not PayNow)" },
  { file: "mobile-90000002-rejected", label: "Rejected payee" },
];

function decodeImageData(data: ImageData): string | null {
  return jsQR(data.data, data.width, data.height, { inversionAttempts: "attemptBoth" })?.data ?? null;
}

async function decodeImage(src: string | Blob): Promise<string | null> {
  const url = typeof src === "string" ? src : URL.createObjectURL(src);
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    const scale = Math.min(1, 1024 / Math.max(img.naturalWidth, img.naturalHeight));
    const w = Math.round(img.naturalWidth * scale);
    const h = Math.round(img.naturalHeight * scale);
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d", { willReadFrequently: true })!;
    ctx.drawImage(img, 0, 0, w, h);
    return decodeImageData(ctx.getImageData(0, 0, w, h));
  } finally {
    if (typeof src !== "string") URL.revokeObjectURL(url);
  }
}

export function Scanner({ back }: { back: Screen }) {
  const video = useRef<HTMLVideoElement>(null);
  const file = useRef<HTMLInputElement>(null);
  const [camera, setCamera] = useState<"starting" | "on" | "off">("starting");
  const lastBad = useRef<{ text: string; at: number } | null>(null);
  const handled = useRef(false);

  const onPayload = (payload: string) => {
    if (handled.current) return;
    const init = qrToInit(payload);
    if (typeof init === "string") {
      const now = Date.now();
      if (lastBad.current?.text === payload && now - lastBad.current.at < 3000) return;
      lastBad.current = { text: payload, at: now };
      toast(init);
      return;
    }
    handled.current = true;
    void dispatch({ kind: "payQR", payload });
  };

  useEffect(() => {
    let stream: MediaStream | null = null;
    let raf = 0;
    let stopped = false;
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d", { willReadFrequently: true })!;
    let lastScan = 0;

    const tick = (t: number) => {
      if (stopped) return;
      const v = video.current;
      if (v && v.readyState >= 2 && t - lastScan > 120) {
        lastScan = t;
        const scale = Math.min(1, 640 / Math.max(v.videoWidth, v.videoHeight));
        canvas.width = Math.round(v.videoWidth * scale);
        canvas.height = Math.round(v.videoHeight * scale);
        ctx.drawImage(v, 0, 0, canvas.width, canvas.height);
        const text = decodeImageData(ctx.getImageData(0, 0, canvas.width, canvas.height));
        if (text) onPayload(text);
      }
      raf = requestAnimationFrame(tick);
    };

    (async () => {
      try {
        if (!navigator.mediaDevices?.getUserMedia) throw new Error("no camera");
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment", width: { ideal: 1280 } },
          audio: false,
        });
        if (stopped) return stream.getTracks().forEach((tr) => tr.stop());
        if (video.current) {
          video.current.srcObject = stream;
          await video.current.play().catch(() => undefined);
        }
        setCamera("on");
        raf = requestAnimationFrame(tick);
      } catch {
        if (!stopped) setCamera("off");
      }
    })();

    return () => {
      stopped = true;
      cancelAnimationFrame(raf);
      stream?.getTracks().forEach((tr) => tr.stop());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const fromImage = async (src: string | Blob) => {
    const text = await decodeImage(src).catch(() => null);
    if (text) onPayload(text);
    else toast("No QR code found in this image");
  };

  return (
    <div className="scanner">
      <header className="navbar navbar-flat">
        <button className="navbar-left" aria-label="Close" data-testid="scanner-close" onClick={() => go(back)}>
          <Close size={26} />
        </button>
        <h1 className="scanner-title">Scan &amp; Pay</h1>
        <span className="navbar-right">
          <Info size={30} />
        </span>
      </header>
      <div className="seg seg-orange">
        <span className="seg-item seg-on">Scan</span>
        <span className="seg-item">Your QR</span>
        <span className="seg-item">Create QR</span>
      </div>
      <div className="camera" data-camera={camera}>
        <video ref={video} playsInline muted />
        {camera !== "on" && (
          <div className="camera-off">
            {camera === "starting" ? "Opening camera…" : "Camera isn't available. Upload a QR image or try a sample."}
          </div>
        )}
        <div className="camera-frame" aria-hidden>
          <i />
          <i />
          <i />
          <i />
        </div>
      </div>
      <div className="scanner-foot">
        <h2>Scan QR Code</h2>
        <p>Line up with the frame to scan NETS, SGQR, PayNow QR codes.</p>
        <button className="pill-btn" onClick={() => file.current?.click()} data-testid="upload">
          UPLOAD A QR IMAGE
        </button>
        <input
          ref={file}
          type="file"
          accept="image/*"
          hidden
          data-testid="upload-input"
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) void fromImage(f);
            e.target.value = "";
          }}
        />
        <div className="samples">
          {SAMPLES.map((s) => (
            <button
              key={s.file}
              className="sample"
              data-testid={`sample-${s.file}`}
              onClick={() => void fromImage(asset(`samples/${s.file}.png`))}
            >
              <img src={asset(`samples/${s.file}.png`)} alt="" />
              <span>{s.label}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
