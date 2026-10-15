# -*- mode: python ; coding: utf-8 -*-

import os
import sys
from pathlib import Path


repo = Path(SPECPATH).parent
platform_resources = Path(os.environ["TE_PLATFORM_RESOURCES"])


def tree_data(source, destination):
    source = Path(source)
    items = []
    for path in source.rglob("*"):
        if path.is_file():
            relative_parent = path.relative_to(source).parent
            target = Path(destination) / relative_parent
            items.append((str(path), str(target)))
    return items


datas = [
    (str(repo / "Resources" / "script"), "te_resources"),
    (str(repo / "Resources" / "metadata_helpers.sh"), "te_resources"),
    (str(repo / "Resources" / "Cussbuster2000.py"), "te_resources"),
]
datas += tree_data(platform_resources, "te_resources")

icon = None
windows_icon = os.environ.get("TE_WINDOWS_ICON")
if sys.platform == "win32" and windows_icon and Path(windows_icon).exists():
    icon = windows_icon

a = Analysis(
    [str(repo / "cross_platform" / "te_tool_app.py")],
    pathex=[str(repo)],
    binaries=[],
    datas=datas,
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="te-tool",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=icon,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="te-tool",
)
