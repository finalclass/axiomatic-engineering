#!/usr/bin/env python3
"""Write the axe sync delta. Does not implement and does not move freeze."""

import hashlib
import json
import re
import shutil
import sys
import tomllib
from pathlib import Path

TEXT_EXT = {".md", ".toml", ".html", ".css", ".js", ".json"}
LABEL_TOKEN = re.compile(r"\[([a-z][a-z0-9_-]*)\]")
LABEL_LINE = re.compile(r"^(?:\[[a-z][a-z0-9_-]*\]\s*)+$")
HEADING = re.compile(r"^(#+)\s+(.*)$")
MD_LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
HREF = re.compile(r"""href=["']([^"']+)["']""", re.I)
FENCE = re.compile(r"```toml\s*\n(.*?)```", re.S)
BUILTIN_PHASE = "impl"
SCREEN_PREFIX = "docs/mockup/screens/"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 16), b""):
            digest.update(chunk)
    return digest.hexdigest()


def snapshot(docs: Path, current: Path) -> None:
    if current.exists():
        shutil.rmtree(current)
    current.mkdir(parents=True)
    assets = []
    for path in sorted(docs.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(docs).as_posix()
        if path.suffix.lower() in TEXT_EXT:
            dest = current / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)
        else:
            assets.append(f"{sha256(path)}  {rel}")
    (current / "ASSETS").write_text("\n".join(assets) + ("\n" if assets else ""), encoding="utf-8")


def text_files(root: Path) -> dict[str, Path]:
    found = {}
    if not root.exists():
        return found
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in TEXT_EXT:
            found[path.relative_to(root).as_posix()] = path
    return found


def asset_map(root: Path) -> dict[str, str]:
    path = root / "ASSETS"
    if not path.exists():
        return {}
    found = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, rel = line.split(None, 1)
        found[rel] = digest
    return found


def defined_labels(main: Path) -> set[str]:
    names = set()
    if not main.exists():
        return names
    for line in main.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^### \[([a-z][a-z0-9_-]*)\]\s*$", line.strip())
        if match:
            names.add(match.group(1))
    return names


def explicit_labels(text: str, defined: set[str]) -> set[str]:
    found = set()
    allowed = defined | {BUILTIN_PHASE}

    def take(names: list[str]) -> None:
        if names and all(name in allowed for name in names):
            found.update(names)

    for line in text.splitlines():
        stripped = line.strip()
        names = LABEL_TOKEN.findall(stripped)
        if LABEL_LINE.match(stripped):
            take(names)
            continue
        heading = HEADING.match(stripped)
        if not heading:
            continue
        body = heading.group(2)
        if "—" in body:
            take(LABEL_TOKEN.findall(body.split("—", 1)[1]))
        elif "[" in body:
            tail = body[body.rfind("["):]
            if LABEL_LINE.match(tail.strip()):
                take(LABEL_TOKEN.findall(tail))
    return found


def default_labels(rel: str) -> set[str]:
    name = Path(rel).name
    if name == "stp.md" or rel.endswith("/stp.md"):
        return {"test"}
    if name.endswith("_page.md") or name.endswith(".tag.md") or rel.startswith(SCREEN_PREFIX):
        return {"impl", "look"}
    return {"impl"}


def headings(text: str) -> list[tuple[int, int, str]]:
    lines = text.splitlines()
    marks = []
    for index, line in enumerate(lines, start=1):
        match = HEADING.match(line.strip())
        if match:
            marks.append((index, len(match.group(1)), match.group(2).strip()))
    spans = []
    for pos, (start, level, title) in enumerate(marks):
        end = len(lines)
        for later_start, later_level, _title in marks[pos + 1:]:
            if later_level <= level:
                end = later_start - 1
                break
        spans.append((start, end, title))
    return spans


def changed_line_numbers(old: str, new: str) -> set[int]:
    import difflib

    old_lines = old.splitlines()
    new_lines = new.splitlines()
    changed = set()
    for tag, _i1, _i2, j1, j2 in difflib.SequenceMatcher(a=old_lines, b=new_lines).get_opcodes():
        if tag == "equal":
            continue
        for line_no in range(j1 + 1, j2 + 1):
            changed.add(line_no)
        if j1 == j2:
            changed.add(min(j1 + 1, max(len(new_lines), 1)))
    return changed


def fences(text: str) -> list[str]:
    return [block.strip() for block in FENCE.findall(text)]


def screen_links(text: str) -> list[str]:
    found = []
    for target in MD_LINK.findall(text) + HREF.findall(text):
        clean = target.split("#", 1)[0].split("?", 1)[0]
        if clean.endswith(".html") and "mockup/screens/" in clean:
            name = clean.split("mockup/screens/", 1)[1]
            rel = SCREEN_PREFIX + name
            if rel not in found:
                found.append(rel)
    return found


def links_resolve(root: Path, rel: str, text: str) -> list[str]:
    missing = []
    source = root / rel
    is_script = source.suffix.lower() == ".js"
    # Mockup scripts are loaded by screens, so their relative links resolve
    # against docs/mockup/screens/, not against the script directory. Targets
    # built by concatenation have no extension and are not file links.
    if is_script and rel.startswith("mockup/"):
        base = root / "mockup" / "screens"
    else:
        base = source.parent
    for target in MD_LINK.findall(text) + HREF.findall(text):
        clean = target.split("#", 1)[0].split("?", 1)[0].strip()
        if not clean or clean.startswith(("#", "/", "mailto:", "http://", "https://", "data:")):
            continue
        if is_script and not Path(clean).suffix:
            continue
        resolved = (base / clean).resolve()
        try:
            resolved.relative_to(root.resolve())
        except ValueError:
            missing.append(f"{rel} -> {target}")
            continue
        if not resolved.exists():
            missing.append(f"{rel} -> {target}")
    return missing


def owning_page(docs: Path, screen_rel: str) -> bool:
    name = Path(screen_rel).name
    for path in docs.rglob("*"):
        if not path.is_file():
            continue
        if path.name.endswith("_page.md") or path.name.endswith(".tag.md"):
            if name in path.read_text(encoding="utf-8", errors="replace"):
                return True
    return False


def write_report(path: Path, status: str, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"status: {status}\n\n{body}", encoding="utf-8")


def main() -> int:
    root = Path.cwd()
    docs = root / "docs"
    current = root / ".axe" / "current"
    freeze = root / ".axe" / "freeze"
    report_path = root / ".axe" / "delta-report.md"
    if not docs.is_dir():
        print("no docs/ directory", file=sys.stderr)
        return 1
    snapshot(docs, current)
    if not freeze.exists():
        shutil.copytree(current, freeze)
        write_report(
            report_path,
            "baseline",
            "Freeze was missing. Current docs are now the baseline. Do not implement.\n",
        )
        print("status: baseline")
        return 2

    old_text = text_files(freeze)
    new_text = text_files(current)
    added = sorted(set(new_text) - set(old_text))
    deleted = sorted(set(old_text) - set(new_text))
    modified = sorted(
        rel
        for rel in set(old_text) & set(new_text)
        if old_text[rel].read_bytes() != new_text[rel].read_bytes()
    )
    old_assets = asset_map(freeze)
    new_assets = asset_map(current)
    asset_changed = sorted(
        rel
        for rel in set(old_assets) | set(new_assets)
        if old_assets.get(rel) != new_assets.get(rel)
    )
    if not added and not deleted and not modified and not asset_changed:
        write_report(report_path, "empty", "Nothing to implement.\n")
        print("status: empty")
        return 0

    defined = defined_labels(docs / "main.md")
    contradictions = []
    file_labels: dict[str, set[str]] = {}
    tests: list[str] = []
    look: list[str] = []
    contract = False

    for rel in added + modified:
        text = new_text[rel].read_text(encoding="utf-8")
        old = old_text[rel].read_text(encoding="utf-8") if rel in old_text else ""
        explicit = explicit_labels(text, defined)
        labels = explicit or default_labels(rel)
        if "test" in labels and "test" not in defined and "test" not in explicit:
            pass
        file_labels[rel] = labels
        if rel.endswith(".json"):
            try:
                json.loads(text)
            except json.JSONDecodeError as error:
                contradictions.append(f"invalid JSON {rel}: {error}")
        contradictions.extend(links_resolve(docs, rel, text))
        old_fences = fences(old)
        new_fences = fences(text)
        if old_fences != new_fences:
            contract = True
            for block in new_fences:
                try:
                    tomllib.loads(block)
                except tomllib.TOMLDecodeError as error:
                    contradictions.append(f"invalid TOML fence in {rel}: {error}")
        changed_lines = changed_line_numbers(old, text)
        spans = headings(text)
        lines = text.splitlines()

        def innermost(line_no: int) -> str:
            section = ""
            best = -1
            for start, end, _title in spans:
                if start <= line_no <= end and start >= best:
                    best = start
                    section = "\n".join(lines[start - 1:end])
            return section

        if "test" in labels:
            hit = []
            for line_no in sorted(changed_lines):
                if 1 <= line_no <= len(lines) and not lines[line_no - 1].strip():
                    continue
                section = innermost(line_no)
                title = section.splitlines()[0].lstrip("#").strip() if section else ""
                if title and title not in hit:
                    hit.append(title)
            if hit:
                for title in hit:
                    tests.append(f"{rel} — {title}")
            else:
                tests.append(rel)
        if "look" in labels:
            nearby = []
            for line_no in sorted(changed_lines):
                for screen in screen_links(innermost(line_no)):
                    if screen not in nearby:
                        nearby.append(screen)
            for screen in nearby:
                if screen not in look:
                    look.append(screen)
        if rel.startswith(SCREEN_PREFIX) and rel.endswith(".html") and not owning_page(docs, rel):
            contradictions.append(f"no owning page or tag for {rel}")

    for rel in deleted:
        file_labels[rel] = set()

    if contradictions:
        body = ["## Contradictions"]
        body.extend(f"- {item}" for item in contradictions)
        write_report(report_path, "contradiction", "\n".join(body) + "\n")
        print("status: contradiction")
        for item in contradictions:
            print(f"- {item}")
        return 1

    lines = ["## Changed"]
    for rel in added:
        labels = ", ".join(sorted(file_labels.get(rel, []))) or "deleted-check"
        lines.append(f"- added: {rel}" + (f" — {labels}" if rel in file_labels else ""))
    for rel in deleted:
        lines.append(f"- deleted: {rel}")
    for rel in modified:
        labels = ", ".join(sorted(file_labels[rel]))
        lines.append(f"- modified: {rel} — {labels}")
    for rel in asset_changed:
        lines.append(f"- asset: {rel}")
    lines.append("")
    lines.append("## Tests to write")
    if tests:
        lines.extend(f"- {item}" for item in tests)
    else:
        lines.append("- none")
    lines.append("")
    lines.append("## Look")
    if look:
        lines.extend(f"- {item}" for item in look)
        lines.append("- viewports: 1440×900, 390×844")
    else:
        lines.append("- none")
    lines.append("")
    lines.append("## Contract")
    lines.append("- yes" if contract else "- no")
    lines.append("")
    lines.append("## Verify")
    lines.append("- build the project")
    lines.append("- format only derived files this delta changes")
    if tests:
        lines.append("- run only the tests written for the headings under Tests to write")
    if look:
        lines.append("- compare the Look screens to the running app at the listed viewports")
    if contract:
        lines.append("- project contract build for the changed fences")
    write_report(report_path, "implement", "\n".join(lines) + "\n")
    print("status: implement")
    print(f"files: {len(added) + len(deleted) + len(modified) + len(asset_changed)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
