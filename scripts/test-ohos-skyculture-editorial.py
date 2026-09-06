#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def normalized(text):
    return re.sub(r"\s+", " ", text).strip()


def main():
    parser = argparse.ArgumentParser(description="Live CLI regression for shipped culture editorial resources")
    parser.add_argument("--device", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--languages", nargs="+", help="Optional shipped-language subset; defaults to all 43")
    args = parser.parse_args()

    def command(name, payload=None):
        invocation = ["node", str(ROOT / "scripts/stellarium-cli.mjs"),
                      "--device", args.device, "--command", name, "--json"]
        if payload is not None:
            invocation.extend(["--payload", payload])
        result = subprocess.run(invocation, capture_output=True, text=True, timeout=45)
        if result.returncode:
            raise RuntimeError(f"{name}: {result.stderr.strip()} {result.stdout[:300]}")
        response = json.loads(result.stdout)
        if response.get("ok") is not True:
            raise RuntimeError(f"{name}: {response}")
        return response

    context = json.loads((ROOT / "data/skyculture_editorial_context.json").read_text())
    languages = args.languages or context["languages"]
    if any(language not in context["languages"] for language in languages):
        parser.error("--languages must contain only shipped languages")
    rules = json.loads((ROOT / "docs/harmonyos/skyculture-passage-revisions.json").read_text())["rules"]
    initial_language = command("getAppState")["language"]
    initial_culture = command("getSkyCultureDetails")["id"]
    report = {"scope": "Six revised passages and editorial notes, not full-corpus translation certification",
              "checks": [], "errors": [], "restored": False}
    try:
        for language in languages:
            response = command("setLanguage", language)
            if response.get("appLanguage") != language:
                raise RuntimeError(f"Language mismatch: {language}: {response}")
            for culture in dict.fromkeys(rule["culture"] for rule in rules):
                command("setSkyCulture", culture)
                details = command("getSkyCultureDetails")
                description = normalized(details.get("description", ""))
                issues = []
                if details.get("id") != culture:
                    issues.append("culture identity mismatch")
                surfaces = {
                    "description": description,
                    "descriptionBlocks": normalized(" ".join(block.get("text", "") for block in details.get("descriptionBlocks", []))),
                    "narration": normalized(details.get("narration", "")),
                }
                for surface, text in surfaces.items():
                    if normalized(context["presentation"][language]["body"]) not in text:
                        issues.append(f"{surface}: localized presentation note missing")
                    if culture in context["chinaRelatedCultureIds"]:
                        if normalized(context["chinaRelated"][language]["body"]) not in text:
                            issues.append(f"{surface}: localized China-related note missing")
                passages = []
                for rule in rules:
                    if rule["culture"] != culture:
                        continue
                    translation = rule["translations"].get(language, {})
                    revised = translation.get("after", rule["sourceAfter"])
                    if normalized(revised) in description:
                        mode = "translated" if translation and language != "en" else "source"
                    elif normalized(rule["sourceAfter"]) in description:
                        mode = "source-fallback"
                    else:
                        mode = "missing"
                        issues.append(f"{rule['id']}: revised passage not found")
                    for old in [rule["sourceBefore"], translation.get("before", "")]:
                        if old and old not in [revised, rule["sourceAfter"]] and normalized(old) in description:
                            issues.append(f"{rule['id']}: old passage still present")
                    passages.append({"id": rule["id"], "mode": mode})
                check = {"language": language, "culture": culture, "issues": issues, "passages": passages}
                report["checks"].append(check)
                print(json.dumps(check, ensure_ascii=False), flush=True)
                args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    except Exception as error:
        report["errors"].append(str(error))
    finally:
        try:
            command("setLanguage", initial_language)
            command("setSkyCulture", initial_culture)
            report["restored"] = True
        except Exception as error:
            report["errors"].append(f"Restore failed: {error}")
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    failed = report["errors"] or any(check["issues"] for check in report["checks"])
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
