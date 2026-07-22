// Crisp 1.5px line icons, monochrome (inherit currentColor). SVG markup
// only -- no emoji, ASCII-safe (RULES.md). Each path is drawn on a 24x24
// viewBox with round caps/joins for a refined, consistent stroke.

export type IconName =
  | "home"
  | "devices"
  | "clipboard"
  | "transfer"
  | "cursor"
  | "bell"
  | "link"
  | "check"
  | "copy"
  | "close"
  | "battery"
  | "bolt"
  | "arrow-down"
  | "arrow-up"
  | "refresh"
  | "signal"
  | "shield"
  | "settings"
  | "globe"
  | "folder"
  | "file"
  | "palette"
  | "phone"
  | "laptop"
  | "desktop"
  | "tablet"
  | "tv"
  | "cpu"
  | "alert"
  | "info"
  | "unlink";

const PATHS: Record<IconName, React.ReactNode> = {
  home: (
    <>
      <path d="M4 10.5 12 4l8 6.5" />
      <path d="M5.5 9.5V19a1 1 0 0 0 1 1h11a1 1 0 0 0 1-1V9.5" />
      <path d="M9.5 20v-6h5v6" />
    </>
  ),
  devices: (
    <>
      <rect x="2.5" y="4.5" width="13" height="9" rx="1.5" />
      <path d="M6 17h6" />
      <rect x="17" y="8.5" width="5" height="11" rx="1.3" />
    </>
  ),
  clipboard: (
    <>
      <rect x="5" y="4" width="14" height="17" rx="2" />
      <path d="M9 4a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 4v0.5H9V4Z" />
      <path d="M8.5 10h7M8.5 13.5h7M8.5 17h4" />
    </>
  ),
  transfer: (
    <>
      <path d="M7 10 4 7l3-3" />
      <path d="M4 7h11a4 4 0 0 1 4 4" />
      <path d="M17 14l3 3-3 3" />
      <path d="M20 17H9a4 4 0 0 1-4-4" />
    </>
  ),
  cursor: (
    <>
      <path d="M5 4l6.5 15.5 2-6 6-2L5 4Z" />
    </>
  ),
  bell: (
    <>
      <path d="M6 9a6 6 0 0 1 12 0c0 4 1.2 5.4 2 6.4.4.5 0 1.1-.7 1.1H4.7c-.7 0-1.1-.6-.7-1.1.8-1 2-2.4 2-6.4Z" />
      <path d="M10 20a2 2 0 0 0 4 0" />
    </>
  ),
  link: (
    <>
      <path d="M9.5 14.5 14.5 9.5" />
      <path d="M8 11 5.5 13.5a3.5 3.5 0 0 0 5 5L13 16" />
      <path d="M16 13l2.5-2.5a3.5 3.5 0 0 0-5-5L11 8" />
    </>
  ),
  check: (
    <>
      <path d="M4.5 12.5 9 17l10.5-11" />
    </>
  ),
  copy: (
    <>
      <rect x="8.5" y="8.5" width="11" height="11" rx="2.2" />
      <path d="M15.5 8.5V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7.5a2 2 0 0 0 2 2h2.5" />
    </>
  ),
  close: (
    <>
      <path d="M6 6l12 12M18 6 6 18" />
    </>
  ),
  battery: (
    <>
      <rect x="2.5" y="7.5" width="16" height="9" rx="2" />
      <path d="M21 10.5v3" />
    </>
  ),
  bolt: (
    <>
      <path d="M12.5 3 5 13h5l-1.5 8 8-11h-5l1-7Z" />
    </>
  ),
  "arrow-down": (
    <>
      <path d="M12 5v13M6.5 12.5 12 18l5.5-5.5" />
    </>
  ),
  "arrow-up": (
    <>
      <path d="M12 19V6M6.5 11.5 12 6l5.5 5.5" />
    </>
  ),
  refresh: (
    <>
      <path d="M20 11a8 8 0 0 0-14-4.5L4 8" />
      <path d="M4 4v4h4" />
      <path d="M4 13a8 8 0 0 0 14 4.5L20 16" />
      <path d="M20 20v-4h-4" />
    </>
  ),
  signal: (
    <>
      <path d="M5 15.5v2M9.5 12v5.5M14 8.5v9M18.5 5v12.5" />
    </>
  ),
  shield: (
    <>
      <path d="M12 3 5 6v5c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6l-7-3Z" />
      <path d="M9 12l2 2 4-4" />
    </>
  ),
  settings: (
    <>
      <circle cx="12" cy="12" r="3" />
      <path d="M12 2.5v2.2M12 19.3v2.2M4.6 4.6l1.6 1.6M17.8 17.8l1.6 1.6M2.5 12h2.2M19.3 12h2.2M4.6 19.4l1.6-1.6M17.8 6.2l1.6-1.6" />
    </>
  ),
  globe: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M3 12h18" />
      <path d="M12 3c2.5 2.4 3.8 5.6 3.8 9s-1.3 6.6-3.8 9c-2.5-2.4-3.8-5.6-3.8-9S9.5 5.4 12 3Z" />
    </>
  ),
  folder: (
    <>
      <path d="M3.5 7.5a2 2 0 0 1 2-2h3.2a2 2 0 0 1 1.5.7l1 1.3H18.5a2 2 0 0 1 2 2v6.5a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2V7.5Z" />
    </>
  ),
  file: (
    <>
      <path d="M6.5 3.5h7l5 5v11a1.5 1.5 0 0 1-1.5 1.5h-10A1.5 1.5 0 0 1 5 19.5v-14A1.5 1.5 0 0 1 6.5 3.5Z" />
      <path d="M13 3.5V8a1 1 0 0 0 1 1h4.5" />
    </>
  ),
  palette: (
    <>
      <path d="M12 3a9 9 0 1 0 0 18c1.1 0 1.8-.9 1.8-1.9 0-.5-.2-.9-.5-1.2-.3-.3-.5-.7-.5-1.2 0-1 .8-1.8 1.8-1.8H16a5 5 0 0 0 5-5c0-3.9-4-7-9-7Z" />
      <circle cx="7.5" cy="12" r="1" />
      <circle cx="10" cy="8" r="1" />
      <circle cx="14.5" cy="8" r="1" />
    </>
  ),
  phone: (
    <>
      <rect x="7" y="2.5" width="10" height="19" rx="2.4" />
      <path d="M10.5 18.5h3" />
    </>
  ),
  laptop: (
    <>
      <rect x="4.5" y="5" width="15" height="10" rx="1.6" />
      <path d="M2.5 18.5h19l-1-2.5H3.5l-1 2.5Z" />
    </>
  ),
  desktop: (
    <>
      <rect x="3.5" y="4.5" width="17" height="11" rx="1.6" />
      <path d="M9 19.5h6M12 15.5v4" />
    </>
  ),
  tablet: (
    <>
      <rect x="5" y="3" width="14" height="18" rx="2.2" />
      <path d="M10.5 18h3" />
    </>
  ),
tv: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M12 22v-2" />
    </>
  ),
  cpu: (
    <>
      <rect x="4.5" y="4.5" width="15" height="15" rx="1.5" />
      <path d="M7 12h10M7 16h10M12 7v10" />
    </>
  ),
  // Distinct from "bell"/"signal": a filled dot under the stem reads as
  // "stop, look at this" for the error-state well (T-601), vs. bell's
  // hollow notification shape.
  alert: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7.5v6" />
      <circle cx="12" cy="16.7" r="0.75" fill="currentColor" stroke="none" />
    </>
  ),
  // Mirrors "alert" but the dot sits above the stem (info convention vs.
  // alert's dot-below-stem), so the two stay visually distinct.
  info: (
    <>
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="7.8" r="0.75" fill="currentColor" stroke="none" />
      <path d="M12 11v6" />
    </>
  ),
  // "link" with a gap plus a strike-through, reading as "disconnect" --
  // previously referenced as the nonexistent "link_off" via an unsafe
  // `as IconName` cast, which rendered no icon at all.
  unlink: (
    <>
      <path d="M8 11 5.5 13.5a3.5 3.5 0 0 0 5 5L13 16" />
      <path d="M16 13l2.5-2.5a3.5 3.5 0 0 0-5-5L11 8" />
      <path d="M4.5 4.5l15 15" />
    </>
  ),
};

interface IconProps {
  name: IconName;
  className?: string;
  strokeWidth?: number;
}

export function Icon({ name, className = "h-5 w-5", strokeWidth = 1.6 }: IconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      {PATHS[name]}
    </svg>
  );
}
