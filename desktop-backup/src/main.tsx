import React from "react";
import ReactDOM from "react-dom/client";
import { App } from "./App";
import { I18nProvider } from "./i18n";
import { applyTheme, getInitialTheme } from "./theme";
import "./styles.css";

// Apply the saved theme before first paint to avoid a flash of the
// default theme.
applyTheme(getInitialTheme());

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <I18nProvider>
      <App />
    </I18nProvider>
  </React.StrictMode>,
);
