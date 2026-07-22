/** @type {import('tailwindcss').Config} */
export default {
  darkMode: "class",
  content: ["./index.html", "./preview.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // Monochrome, black-and-grey only. No blue/purple/gold/amber.
        // Shade tokens are CSS variables (RGB triplets) so the Settings
        // panel can swap themes at runtime; see styles.css :root and the
        // [data-theme="..."] overrides. The <alpha-value> placeholder
        // keeps Tailwind alpha modifiers (e.g. bg-surface/60) working.
        canvas: "rgb(var(--canvas) / <alpha-value>)",
        surface: {
          DEFAULT: "rgb(var(--surface) / <alpha-value>)",
          raised: "rgb(var(--surface-raised) / <alpha-value>)",
          overlay: "rgb(var(--surface-overlay) / <alpha-value>)",
          hover: "rgb(var(--surface-hover) / <alpha-value>)",
        },
        line: {
          DEFAULT: "rgba(255,255,255,0.08)",
          strong: "rgba(255,255,255,0.14)",
          faint: "rgba(255,255,255,0.05)",
        },
        ink: {
          DEFAULT: "rgb(var(--ink) / <alpha-value>)",
          muted: "rgb(var(--ink-muted) / <alpha-value>)",
          faint: "rgb(var(--ink-faint) / <alpha-value>)",
          ghost: "rgb(var(--ink-ghost) / <alpha-value>)",
        },
        // Primary action: near-white surface with black text (monochrome
        // high-contrast, deliberately NOT a colored accent).
        paper: {
          DEFAULT: "rgb(var(--paper) / <alpha-value>)",
          hover: "rgb(var(--paper-hover) / <alpha-value>)",
        },
        // Functional-only muted red for error/danger; nothing decorative.
        danger: {
          DEFAULT: "#e0575b",
          soft: "rgba(224,87,91,0.14)",
        },
      },
      fontFamily: {
        // Deliberately not Inter. A refined system grotesque stack.
        sans: [
          "ui-sans-serif",
          "-apple-system",
          "BlinkMacSystemFont",
          "SF Pro Display",
          "Segoe UI",
          "Roboto",
          "Helvetica Neue",
          "Arial",
          "sans-serif",
        ],
        mono: [
          "ui-monospace",
          "SF Mono",
          "SFMono-Regular",
          "JetBrains Mono",
          "Menlo",
          "Consolas",
          "monospace",
        ],
      },
      letterSpacing: {
        tightest: "-0.03em",
      },
      boxShadow: {
        // Soft, low, monochrome elevation.
        card: "0 1px 0 0 rgba(255,255,255,0.04) inset, 0 8px 24px -12px rgba(0,0,0,0.7)",
        pop: "0 24px 60px -20px rgba(0,0,0,0.85), 0 1px 0 0 rgba(255,255,255,0.06) inset",
        glow: "0 0 0 1px rgba(255,255,255,0.06), 0 0 32px -8px rgba(255,255,255,0.10)",
      },
      keyframes: {
        "fade-in": {
          from: { opacity: "0", transform: "translateY(4px)" },
          to: { opacity: "1", transform: "translateY(0)" },
        },
        "scale-in": {
          from: { opacity: "0", transform: "scale(0.97)" },
          to: { opacity: "1", transform: "scale(1)" },
        },
        "pulse-ring": {
          "0%": { boxShadow: "0 0 0 0 rgba(255,255,255,0.28)" },
          "70%": { boxShadow: "0 0 0 6px rgba(255,255,255,0)" },
          "100%": { boxShadow: "0 0 0 0 rgba(255,255,255,0)" },
        },
        shimmer: {
          "100%": { transform: "translateX(100%)" },
        },
      },
      animation: {
        "fade-in": "fade-in 0.32s cubic-bezier(0.16,1,0.3,1)",
        "scale-in": "scale-in 0.2s cubic-bezier(0.16,1,0.3,1)",
        "pulse-ring": "pulse-ring 2.4s cubic-bezier(0.4,0,0.2,1) infinite",
      },
    },
  },
  plugins: [],
};
