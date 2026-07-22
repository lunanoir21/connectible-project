import { describe, expect, it, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { Sidebar } from "./Sidebar";

describe("Sidebar", () => {
  it("renders every nav item plus the pinned settings entry", () => {
    render(<Sidebar active="home" onSelect={vi.fn()} counts={{}} />);
    expect(screen.getByText("Home")).toBeInTheDocument();
    expect(screen.getByText("Devices")).toBeInTheDocument();
    expect(screen.getByText("Clipboard")).toBeInTheDocument();
    expect(screen.getByText("Transfers")).toBeInTheDocument();
    expect(screen.getByText("Remote input")).toBeInTheDocument();
    expect(screen.getByText("Notifications")).toBeInTheDocument();
    expect(screen.getByText("Doctor")).toBeInTheDocument();
    expect(screen.getByText("Settings")).toBeInTheDocument();
  });

  it("marks the active panel with aria-current, and no other item", () => {
    render(<Sidebar active="clipboard" onSelect={vi.fn()} counts={{}} />);
    expect(screen.getByRole("button", { name: "Clipboard" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("button", { name: "Home" })).not.toHaveAttribute("aria-current");
    expect(screen.getByRole("button", { name: "Settings" })).not.toHaveAttribute("aria-current");
  });

  it("marks settings active when it is the selected panel", () => {
    render(<Sidebar active="settings" onSelect={vi.fn()} counts={{}} />);
    expect(screen.getByRole("button", { name: "Settings" })).toHaveAttribute("aria-current", "page");
  });

  it("shows a real badge count for a panel that has one, and no badge for panels at zero", () => {
    render(<Sidebar active="home" onSelect={vi.fn()} counts={{ notifications: 3, clipboard: 0 }} />);
    expect(screen.getByText("3")).toBeInTheDocument();
    // Clipboard has count 0 -- distinct from a panel with a real count,
    // it must not render a badge at all.
    const clipboardButton = screen.getByRole("button", { name: "Clipboard" });
    expect(clipboardButton.textContent).toBe("Clipboard");
  });

  it("calls onSelect with the clicked panel id", () => {
    const onSelect = vi.fn();
    render(<Sidebar active="home" onSelect={onSelect} counts={{}} />);
    fireEvent.click(screen.getByRole("button", { name: "Doctor" }));
    expect(onSelect).toHaveBeenCalledWith("doctor");
    fireEvent.click(screen.getByRole("button", { name: "Settings" }));
    expect(onSelect).toHaveBeenCalledWith("settings");
  });
});
