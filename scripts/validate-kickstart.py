#!/usr/bin/env python3
"""Validate a kickstart file against one Fedora kickstart version."""

import sys

try:
    from pykickstart.errors import KickstartError
    from pykickstart.parser import KickstartParser
    from pykickstart.version import makeVersion
except ImportError:
    sys.exit("pykickstart is required. Install it with: make deps")


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} F43 kickstart.ks")
    version, path = sys.argv[1], sys.argv[2]
    parser = KickstartParser(makeVersion(version))
    try:
        parser.readKickstart(path)
    except KickstartError as exc:
        sys.exit(f"{path}: {exc}")
    print(f"{path}: valid for {version}")


if __name__ == "__main__":
    main()
