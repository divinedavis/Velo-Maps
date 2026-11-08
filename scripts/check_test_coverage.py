#!/usr/bin/env python3
"""Keep the UI tests in step with the app, from source (no simulator):

  * STALE: a UI test queries an identifier/label that no string in the app can produce
    (feature removed or renamed; the test now waits for something that never appears).
    `XCTAssertFalse(...)` lines are deliberate "must be gone" checks and are skipped.
  * UNCOVERED: an app source file that sets accessibility identifiers, none of which any
    UI test queries — a new screen has to come with at least one test.

Exit 1 with a list on any failure.
"""
import glob, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LITERAL = re.compile(r'"((?:\\\((?:[^()]|\([^()]*\))*\)|\\.|[^"\\])*)"')
QUERY = re.compile(r'\["((?:[^"\\]|\\.)*)"\]')
IDENT = re.compile(r'accessibilityIdentifier\("((?:\\\((?:[^()]|\([^()]*\))*\)|[^"\\])*)"\)')
INTERP = re.compile(r'\\\((?:[^()]|\([^()]*\))*\)')


def as_regex(lit):
    parts = INTERP.split(lit)
    return re.compile(".+".join(re.escape(p) for p in parts) + r"\Z")


def main():
    app_files = glob.glob(os.path.join(ROOT, "VeloMaps", "**", "*.swift"), recursive=True)
    test_files = glob.glob(os.path.join(ROOT, "VeloMapsUITests", "*.swift"))
    app_literals = {m.group(1) for f in app_files for m in LITERAL.finditer(open(f).read())}
    patterns = [as_regex(l) for l in app_literals]

    queried, stale = set(), []
    for f in test_files:
        for n, line in enumerate(open(f), 1):
            if "XCTAssertFalse" in line:
                continue
            for q in QUERY.findall(line):
                queried.add(q)
                if not any(p.match(q) for p in patterns):
                    stale.append(f"{os.path.basename(f)}:{n}: \"{q}\"")

    uncovered = []
    for f in app_files:
        ids = IDENT.findall(open(f).read())
        if ids and not any(as_regex(i).match(q) for i in ids for q in queried):
            uncovered.append(f"{os.path.relpath(f, ROOT)}: {', '.join(sorted(set(ids)))}")

    for s in stale: print("STALE     ", s)
    for u in uncovered: print("UNCOVERED ", u)
    if stale or uncovered:
        return 1
    print(f"test coverage OK — {len(queried)} queried strings, {len(app_files)} app files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
