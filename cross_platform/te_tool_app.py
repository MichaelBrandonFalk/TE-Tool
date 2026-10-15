#!/usr/bin/env python3
"""Cross-platform desktop launcher for the TE Tool QC engine."""

from __future__ import annotations

import argparse
import os
import queue
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
from pathlib import Path
from typing import Iterable

import tkinter as tk
from tkinter import filedialog, messagebox, ttk


APP_NAME = "TE Tool"
APP_VERSION = "11.11"
VIDEO_EXTENSIONS = {".mov", ".mp4", ".mxf", ".m4v"}

CHECKS = (
    ("Phase 1", "PHASE1_ON", True, False),
    ("I-Frame", "IFRAME_ON", True, False),
    ("Caption Profanity", "CAPTIONPROFANITY_ON", True, True),
    ("Phase 2", "PHASE2_ON", True, False),
    ("Luma IRE", "LUMAIRE_ON", True, False),
    ("True Peaks", "TRUEPEAKS_ON", True, False),
    ("Advanced Continuity", "ADVANCEDCONTINUITY_ON", False, False),
    ("Advanced Luma IRE", "ADVANCEDLUMAIRE_ON", False, False),
    ("Advanced Chroma", "ADVANCEDCHROMA_ON", False, False),
)


def app_root() -> Path:
    override = os.environ.get("TE_RESOURCE_DIR")
    if override:
        return Path(override).expanduser().resolve()
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS")) / "te_resources"
    return Path(__file__).resolve().parents[1] / "Resources"


def logs_dir() -> Path:
    desktop = Path.home() / "Desktop"
    base = desktop if desktop.exists() else Path.home()
    return base / "TE_Logs"


def msys_path(path: Path | str) -> str:
    value = Path(path).resolve().as_posix()
    if sys.platform == "win32" and len(value) >= 3 and value[1:3] == ":/":
        return f"/{value[0].lower()}{value[2:]}"
    return value


def bash_executable(resources: Path) -> Path:
    if sys.platform == "win32":
        return resources / "runtime" / "usr" / "bin" / "bash.exe"
    return Path("/bin/bash")


def tool_path(resources: Path, name: str) -> Path | None:
    suffixes = (".exe", "") if sys.platform == "win32" else ("",)
    for suffix in suffixes:
        candidate = resources / f"{name}{suffix}"
        if candidate.is_file():
            return candidate
    if sys.platform != "win32":
        system_tool = shutil.which(name)
        if system_tool:
            return Path(system_tool)
    return None


def app_icon_path(resources: Path) -> Path | None:
    icon = resources / "app-icon.png"
    return icon if icon.is_file() else None


def manual_path(resources: Path) -> Path | None:
    manual = resources / "TE TOOLS User Manual.pdf"
    return manual if manual.is_file() else None


def open_path(path: Path) -> None:
    if sys.platform == "win32":
        os.startfile(path)  # type: ignore[attr-defined]
    elif sys.platform == "darwin":
        subprocess.Popen(["open", str(path)])
    else:
        subprocess.Popen(["xdg-open", str(path)])


def scan_environment(resources: Path, test_type: str, checks: dict[str, bool]) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "TE_NONINTERACTIVE": "1",
            "TE_TEST_TYPE": test_type,
            "TE_VERBOSE": "0",
            "TE_LOG_DIR": msys_path(logs_dir()),
            "TE_TMP_DIR": msys_path(Path(tempfile.gettempdir())),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "PYTHONUTF8": "1",
        }
    )
    for _label, key, _default, _broadcast_only in CHECKS:
        env[f"TE_{key}"] = "1" if checks.get(key, False) else "0"

    if sys.platform == "win32":
        runtime_bin = resources / "runtime" / "usr" / "bin"
        env["PATH"] = os.pathsep.join((str(runtime_bin), str(resources), env.get("PATH", "")))
        env["HOME"] = Path.home().as_posix()
    return env


def scan_command(resources: Path, files: Iterable[Path]) -> list[str]:
    bash = bash_executable(resources)
    script = resources / "script"
    return [str(bash), msys_path(script), *(msys_path(path) for path in files)]


def diagnostic_errors(resources: Path) -> list[str]:
    errors: list[str] = []
    required_files = ("script", "metadata_helpers.sh")
    for name in required_files:
        if not (resources / name).is_file():
            errors.append(f"Missing resource: {name}")

    bash = bash_executable(resources)
    if not bash.is_file():
        errors.append(f"Missing Bash runtime: {bash}")

    for name in ("ffmpeg", "ffprobe", "jq", "exiftool"):
        if tool_path(resources, name) is None:
            errors.append(f"Missing bundled tool: {name}")
    return errors


def run_headless(files: list[Path], test_type: str, phase1_only: bool) -> int:
    resources = app_root()
    errors = diagnostic_errors(resources)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 2

    checks = {key: default for _label, key, default, _broadcast_only in CHECKS}
    if phase1_only:
        checks = {key: key == "PHASE1_ON" for _label, key, _default, _broadcast_only in CHECKS}
    completed = subprocess.run(
        scan_command(resources, files),
        env=scan_environment(resources, test_type, checks),
        check=False,
    )
    return completed.returncode


class TEToolApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.resources = app_root()
        self.files: list[Path] = []
        self.process: subprocess.Popen[str] | None = None
        self.events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.stop_requested = False
        self.app_icon: tk.PhotoImage | None = None
        self.header_icon: tk.PhotoImage | None = None

        self.root.title(f"{APP_NAME} Version {APP_VERSION}")
        self.root.geometry("1060x760")
        self.root.minsize(840, 620)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        self.test_type = tk.StringVar(value="SVOD")
        self.check_vars = {
            key: tk.BooleanVar(value=default)
            for _label, key, default, _broadcast_only in CHECKS
        }
        self.status = tk.StringVar(value="Ready")
        self.progress = tk.StringVar(value="No files selected")
        self.check_widgets: dict[str, ttk.Checkbutton] = {}

        self._configure_style()
        self._build_ui()
        self._load_icon()
        self._update_test_type()
        self.root.after(100, self._drain_events)

    def _configure_style(self) -> None:
        style = ttk.Style(self.root)
        if sys.platform == "win32":
            style.theme_use("vista")
        elif "clam" in style.theme_names():
            style.theme_use("clam")
        style.configure("Title.TLabel", font=("TkDefaultFont", 22, "bold"))
        style.configure("Version.TLabel", foreground="#176f68", font=("TkDefaultFont", 11, "bold"))
        style.configure("Section.TLabelframe.Label", font=("TkDefaultFont", 11, "bold"))
        style.configure("Primary.TButton", font=("TkDefaultFont", 10, "bold"), padding=(16, 8))
        style.configure("Toolbar.TButton", padding=(10, 6))

    def _build_ui(self) -> None:
        shell = ttk.Frame(self.root, padding=18)
        shell.grid(row=0, column=0, sticky="nsew")
        self.root.rowconfigure(0, weight=1)
        self.root.columnconfigure(0, weight=1)
        shell.columnconfigure(0, weight=1)
        shell.rowconfigure(3, weight=1)

        header = ttk.Frame(shell)
        header.grid(row=0, column=0, sticky="ew", pady=(0, 14))
        header.columnconfigure(1, weight=1)
        self.icon_label = ttk.Label(header)
        self.icon_label.grid(row=0, column=0, rowspan=2, sticky="w", padx=(0, 12))
        ttk.Label(header, text=APP_NAME, style="Title.TLabel").grid(row=0, column=1, sticky="w")
        ttk.Label(header, text=f"Version {APP_VERSION}", style="Version.TLabel").grid(row=1, column=1, sticky="w")

        source = ttk.LabelFrame(shell, text="Media Files", style="Section.TLabelframe", padding=10)
        source.grid(row=1, column=0, sticky="nsew", pady=(0, 12))
        source.columnconfigure(0, weight=1)
        source.rowconfigure(1, weight=1)

        toolbar = ttk.Frame(source)
        toolbar.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 8))
        ttk.Button(toolbar, text="Add Files", command=self.add_files, style="Toolbar.TButton").pack(side="left")
        ttk.Button(toolbar, text="Add Folder", command=self.add_folder, style="Toolbar.TButton").pack(side="left", padx=(8, 0))
        ttk.Button(toolbar, text="Remove", command=self.remove_selected, style="Toolbar.TButton").pack(side="left", padx=(8, 0))
        ttk.Button(toolbar, text="Clear", command=self.clear_files, style="Toolbar.TButton").pack(side="left", padx=(8, 0))
        ttk.Label(toolbar, textvariable=self.progress).pack(side="right")

        self.file_list = tk.Listbox(source, height=7, activestyle="none", selectmode=tk.EXTENDED)
        self.file_list.grid(row=1, column=0, sticky="nsew")
        file_scroll = ttk.Scrollbar(source, orient="vertical", command=self.file_list.yview)
        file_scroll.grid(row=1, column=1, sticky="ns")
        self.file_list.configure(yscrollcommand=file_scroll.set)

        options = ttk.Frame(shell)
        options.grid(row=2, column=0, sticky="ew", pady=(0, 12))
        options.columnconfigure(1, weight=1)

        type_box = ttk.LabelFrame(options, text="Test Type", style="Section.TLabelframe", padding=10)
        type_box.grid(row=0, column=0, sticky="nsw", padx=(0, 12))
        ttk.Radiobutton(type_box, text="SVOD", value="SVOD", variable=self.test_type, command=self._update_test_type).pack(anchor="w")
        ttk.Radiobutton(type_box, text="Broadcast Master", value="Broadcast Master", variable=self.test_type, command=self._update_test_type).pack(anchor="w", pady=(5, 0))

        checks_box = ttk.LabelFrame(options, text="Checks", style="Section.TLabelframe", padding=10)
        checks_box.grid(row=0, column=1, sticky="nsew")
        for index, (label, key, _default, _broadcast_only) in enumerate(CHECKS):
            widget = ttk.Checkbutton(checks_box, text=label, variable=self.check_vars[key])
            widget.grid(row=index // 3, column=index % 3, sticky="w", padx=(0, 22), pady=3)
            self.check_widgets[key] = widget

        output = ttk.LabelFrame(shell, text="Results", style="Section.TLabelframe", padding=10)
        output.grid(row=3, column=0, sticky="nsew")
        output.columnconfigure(0, weight=1)
        output.rowconfigure(0, weight=1)
        self.log = tk.Text(output, wrap="none", font=("TkFixedFont", 11), padx=8, pady=8, state="disabled")
        self.log.grid(row=0, column=0, sticky="nsew")
        log_y = ttk.Scrollbar(output, orient="vertical", command=self.log.yview)
        log_y.grid(row=0, column=1, sticky="ns")
        log_x = ttk.Scrollbar(output, orient="horizontal", command=self.log.xview)
        log_x.grid(row=1, column=0, sticky="ew")
        self.log.configure(yscrollcommand=log_y.set, xscrollcommand=log_x.set)
        self.log.tag_configure("pass", background="#dcefd7", foreground="#172019")
        self.log.tag_configure("warning", background="#fde9b5", foreground="#241d0d")
        self.log.tag_configure("fail", background="#eadcf3", foreground="#211827")
        self.log.tag_configure("info", foreground="#1d4f61")

        footer = ttk.Frame(shell)
        footer.grid(row=4, column=0, sticky="ew", pady=(12, 0))
        footer.columnconfigure(1, weight=1)
        ttk.Label(footer, textvariable=self.status).grid(row=0, column=0, sticky="w")
        if manual_path(self.resources) is not None:
            ttk.Button(footer, text="User Manual", command=self.open_manual, style="Toolbar.TButton").grid(row=0, column=2, padx=(8, 0))
        ttk.Button(footer, text="Open Logs", command=self.open_logs, style="Toolbar.TButton").grid(row=0, column=3, padx=(8, 0))
        self.stop_button = ttk.Button(footer, text="Stop", command=self.stop_scan, state="disabled", style="Toolbar.TButton")
        self.stop_button.grid(row=0, column=4, padx=(8, 0))
        self.run_button = ttk.Button(footer, text="Run Checks", command=self.run_scan, style="Primary.TButton")
        self.run_button.grid(row=0, column=5, padx=(8, 0))

    def _load_icon(self) -> None:
        icon = app_icon_path(self.resources)
        if icon is None:
            return
        try:
            self.app_icon = tk.PhotoImage(file=str(icon))
            self.header_icon = self.app_icon.subsample(16, 16)
            self.icon_label.configure(image=self.header_icon)
            self.root.iconphoto(True, self.app_icon)
        except tk.TclError:
            self.app_icon = None
            self.header_icon = None

    def _update_test_type(self) -> None:
        caption = self.check_widgets.get("CAPTIONPROFANITY_ON")
        if caption is None:
            return
        if self.test_type.get() == "Broadcast Master":
            caption.configure(state="normal")
        else:
            self.check_vars["CAPTIONPROFANITY_ON"].set(False)
            caption.configure(state="disabled")

    def _refresh_files(self) -> None:
        self.file_list.delete(0, tk.END)
        for path in self.files:
            self.file_list.insert(tk.END, str(path))
        count = len(self.files)
        self.progress.set(f"{count} file{'s' if count != 1 else ''} selected" if count else "No files selected")

    def _add_paths(self, paths: Iterable[Path]) -> None:
        known = {str(path).casefold() for path in self.files}
        for path in paths:
            resolved = path.expanduser().resolve()
            key = str(resolved).casefold()
            if resolved.is_file() and resolved.suffix.lower() in VIDEO_EXTENSIONS and key not in known:
                self.files.append(resolved)
                known.add(key)
        self.files.sort(key=lambda item: item.name.casefold())
        self._refresh_files()

    def add_files(self) -> None:
        selected = filedialog.askopenfilenames(
            title="Select media files",
            filetypes=(("Video files", "*.mov *.mp4 *.mxf *.m4v"), ("All files", "*.*")),
        )
        self._add_paths(Path(path) for path in selected)

    def add_folder(self) -> None:
        selected = filedialog.askdirectory(title="Select a media folder")
        if not selected:
            return
        folder = Path(selected)
        self._add_paths(path for path in folder.rglob("*") if path.suffix.lower() in VIDEO_EXTENSIONS)

    def remove_selected(self) -> None:
        indexes = set(self.file_list.curselection())
        self.files = [path for index, path in enumerate(self.files) if index not in indexes]
        self._refresh_files()

    def clear_files(self) -> None:
        if self.process is None:
            self.files.clear()
            self._refresh_files()

    def _append_log(self, line: str) -> None:
        upper = line.upper()
        if "FAIL" in upper or "❌" in line:
            tag = "fail"
        elif "WARNING" in upper or "⚠" in line or "CLOSE" in upper:
            tag = "warning"
        elif "PASS" in upper or "✅" in line:
            tag = "pass"
        else:
            tag = "info" if line.startswith("[") else ""
        self.log.configure(state="normal")
        self.log.insert(tk.END, line, tag)
        if not line.endswith("\n"):
            self.log.insert(tk.END, "\n", tag)
        self.log.see(tk.END)
        self.log.configure(state="disabled")

    def run_scan(self) -> None:
        if self.process is not None:
            return
        if not self.files:
            messagebox.showinfo(APP_NAME, "Select at least one video file or folder first.")
            return
        errors = diagnostic_errors(self.resources)
        if errors:
            messagebox.showerror(APP_NAME, "The app package is incomplete:\n\n" + "\n".join(errors))
            return

        checks = {key: variable.get() for key, variable in self.check_vars.items()}
        if not any(checks.values()):
            messagebox.showinfo(APP_NAME, "Select at least one check.")
            return

        self.stop_requested = False
        self.run_button.configure(state="disabled")
        self.stop_button.configure(state="normal")
        self.status.set("Starting checks...")
        self.progress.set(f"0 of {len(self.files)} complete")
        self.log.configure(state="normal")
        self.log.delete("1.0", tk.END)
        self.log.configure(state="disabled")

        test_type = self.test_type.get()
        thread = threading.Thread(target=self._scan_worker, args=(checks, test_type), daemon=True)
        thread.start()

    def _scan_worker(self, checks: dict[str, bool], test_type: str) -> None:
        creationflags = subprocess.CREATE_NEW_PROCESS_GROUP if sys.platform == "win32" else 0
        try:
            self.process = subprocess.Popen(
                scan_command(self.resources, self.files),
                env=scan_environment(self.resources, test_type, checks),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
                creationflags=creationflags,
                start_new_session=sys.platform != "win32",
            )
            assert self.process.stdout is not None
            completed = 0
            for line in self.process.stdout:
                self.events.put(("line", line))
                if line.startswith("Check complete:"):
                    completed += 1
                    self.events.put(("progress", completed))
            code = self.process.wait()
            self.events.put(("done", code))
        except Exception as exc:  # surfaced in the GUI
            self.events.put(("error", str(exc)))

    def _drain_events(self) -> None:
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "line":
                    self._append_log(str(payload))
                elif kind == "progress":
                    self.progress.set(f"{payload} of {len(self.files)} complete")
                elif kind == "done":
                    self._finish_scan(int(payload))
                elif kind == "error":
                    self._finish_scan(1)
                    messagebox.showerror(APP_NAME, f"The scan could not start:\n\n{payload}")
        except queue.Empty:
            pass
        self.root.after(100, self._drain_events)

    def _finish_scan(self, code: int) -> None:
        self.process = None
        self.run_button.configure(state="normal")
        self.stop_button.configure(state="disabled")
        if self.stop_requested:
            self.status.set("Scan stopped")
        elif code == 0:
            self.status.set("Checks complete")
            self.progress.set(f"{len(self.files)} of {len(self.files)} complete")
        else:
            self.status.set(f"Checks ended with error code {code}")

    def stop_scan(self) -> None:
        process = self.process
        if process is None:
            return
        self.stop_requested = True
        self.status.set("Stopping...")
        if sys.platform == "win32":
            subprocess.run(
                ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        else:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    def open_logs(self) -> None:
        target = logs_dir()
        target.mkdir(parents=True, exist_ok=True)
        try:
            open_path(target)
        except OSError as exc:
            messagebox.showerror(APP_NAME, f"Could not open the logs folder:\n\n{exc}")

    def open_manual(self) -> None:
        target = manual_path(self.resources)
        if target is None:
            messagebox.showerror(APP_NAME, "The user manual is not included in this package.")
            return
        try:
            open_path(target)
        except OSError as exc:
            messagebox.showerror(APP_NAME, f"Could not open the user manual:\n\n{exc}")

    def close(self) -> None:
        if self.process is not None:
            if not messagebox.askyesno(APP_NAME, "A scan is still running. Stop it and close the app?"):
                return
            self.stop_scan()
        self.root.destroy()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=f"{APP_NAME} Version {APP_VERSION}")
    parser.add_argument("files", nargs="*", type=Path)
    parser.add_argument("--diagnostics", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--phase1-only", action="store_true")
    parser.add_argument("--test-type", choices=("SVOD", "Broadcast Master"), default="SVOD")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    resources = app_root()
    if args.diagnostics or args.self_test:
        errors = diagnostic_errors(resources)
        if errors:
            for error in errors:
                print(error, file=sys.stderr)
            return 2
        print(f"{APP_NAME} Version {APP_VERSION}: resources OK")
        return 0
    if args.headless:
        if not args.files:
            print("No media files supplied.", file=sys.stderr)
            return 2
        return run_headless(args.files, args.test_type, args.phase1_only)

    root = tk.Tk()
    TEToolApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
