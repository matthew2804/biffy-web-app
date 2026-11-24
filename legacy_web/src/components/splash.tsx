import { useEffect, useState } from "react";
import beeUrl from "@/assets/biffy-logo.png";

const SPLASH_MS = 1000;

export function Splash() {
  const [visible, setVisible] = useState(true);
  const [leaving, setLeaving] = useState(false);

  useEffect(() => {
    const leaveTimer = setTimeout(() => setLeaving(true), SPLASH_MS);
    const removeTimer = setTimeout(() => setVisible(false), SPLASH_MS + 500);
    return () => {
      clearTimeout(leaveTimer);
      clearTimeout(removeTimer);
    };
  }, []);

  if (!visible) return null;

  return (
    <div
      className={`splash-screen ${leaving ? "splash-screen--leaving" : ""}`}
      aria-hidden={leaving}
    >
      <div className="splash-blob splash-blob--soft" />
      <div className="splash-blob splash-blob--warm" />
      <img
        src={beeUrl}
        alt=""
        draggable={false}
        className="splash-bee"
      />
      <h1 className="splash-wordmark">
        BIFFY<span className="splash-dot">.</span>
      </h1>
      <p className="splash-tagline">Comida que llega volando</p>
      <div className="splash-trail" />
    </div>
  );
}
