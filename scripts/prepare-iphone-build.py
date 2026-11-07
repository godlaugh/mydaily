#!/usr/bin/env python3
"""Generate an isolated, automatically signed iPhone test project using XcodeGen."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", required=True, help="Your unique test app ID, e.g. dev.yourname.alogtest")
    parser.add_argument("--team", default="", help="Apple development Team ID; may also be selected in Xcode later")
    parser.add_argument("--xcodegen", default=shutil.which("xcodegen"), help="Path to XcodeGen")
    args = parser.parse_args()
    if not args.xcodegen:
        parser.error("Install XcodeGen or pass --xcodegen /path/to/xcodegen")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        parser.error("--bundle-id must be a reverse-domain app identifier")
    if args.team and not re.fullmatch(r"[A-Z0-9]{10}", args.team):
        parser.error("--team must be a 10-character Apple Team ID")

    root = Path(__file__).resolve().parents[1]
    output = root / ".build" / "iphone-test"
    output.mkdir(parents=True, exist_ok=True)
    raw = subprocess.check_output(
        [args.xcodegen, "dump", "--spec", str(root / "project.yml"), "--type", "json", "--no-env"],
        cwd=root,
    )
    spec = json.loads(raw)
    original_id = spec["targets"]["ALog"]["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"]
    if args.bundle_id == original_id:
        parser.error("Use a separate test bundle ID so the installed App Store app keeps its data")

    spec["name"] = "ALogTest"
    # The personal-device project tests the iPhone app without requiring a Watch
    # runtime or creating additional Watch/widget App IDs on a Personal Team.
    kept = {"ALog", "ALogTests", "SnapshotTests"}
    spec["targets"] = {name: target for name, target in spec["targets"].items() if name in kept}
    spec["schemes"].pop("ALogWatch", None)
    signing_keys = {"CODE_SIGN_STYLE", "CODE_SIGN_IDENTITY", "DEVELOPMENT_TEAM",
                    "PROVISIONING_PROFILE", "PROVISIONING_PROFILE_SPECIFIER"}

    def clear_signing(settings):
        for key in signing_keys:
            settings.pop(key, None)
        for key, value in settings.items():
            if isinstance(value, dict):
                clear_signing(value)
            elif isinstance(value, (int, float)) and not isinstance(value, bool):
                # JSON's numeric 1 can bridge to Bool inside XcodeGen, producing
                # CURRENT_PROJECT_VERSION=YES. Build settings are textual values.
                settings[key] = str(value)

    clear_signing(spec["settings"])
    spec["settings"].update({
        "CODE_SIGN_STYLE": "Automatic",
        "CODE_SIGN_IDENTITY": "Apple Development",
        "DEVELOPMENT_TEAM": args.team,
    })

    for name, target in spec["targets"].items():
        target["dependencies"] = [
            dependency for dependency in target.get("dependencies", [])
            if "target" not in dependency or dependency["target"] in kept
        ]
        settings = target.setdefault("settings", {})
        clear_signing(settings)
        base = settings.setdefault("base", {}) if "base" in settings or "configs" in settings else settings
        suffix = "" if name == "ALog" else "." + name.lower()
        base["PRODUCT_BUNDLE_IDENTIFIER"] = args.bundle_id + suffix

        # Generated plists live beside the test project; original release plists
        # must neither be modified nor copied as duplicate bundle resources.
        sources = []
        for source in target.get("sources", []):
            source = {"path": source} if isinstance(source, str) else dict(source)
            source.setdefault("excludes", []).append("Info.plist")
            sources.append(source)
        target["sources"] = sources
        if "info" in target:
            target["info"]["path"] = str(output / (name + "-Info.plist"))
        if "INFOPLIST_FILE" in base:
            base["INFOPLIST_FILE"] = str(root / base["INFOPLIST_FILE"])

    properties = spec["targets"]["ALog"]["info"]["properties"]
    properties["CFBundleDisplayName"] = "ALog Test"
    properties["CFBundleURLTypes"] = [{
        "CFBundleTypeRole": "Editor", "CFBundleURLName": args.bundle_id,
        "CFBundleURLSchemes": ["alog-test"],
    }]
    spec_path = output / "project.json"
    spec_path.write_text(json.dumps(spec, indent=2) + "\n")
    subprocess.run([
        args.xcodegen, "generate", "--spec", str(spec_path),
        "--project-root", str(root), "--project", str(output),
    ], cwd=root, check=True)
    print(f"Open {output / 'ALogTest.xcodeproj'}")
    print("Select the ALog scheme, your iPhone, and your Team under Signing & Capabilities; then Run.")


if __name__ == "__main__":
    main()
