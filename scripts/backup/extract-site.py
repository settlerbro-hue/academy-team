"""Extract only regular site files; reject traversal, links and unexpected roots."""
import sys, tarfile
from pathlib import Path, PurePosixPath

archive, target = sys.argv[1:]
destination = Path(target).resolve()
with tarfile.open(archive, "r:gz") as source:
    members = source.getmembers()
    for member in members:
        p = PurePosixPath(member.name)
        if p.is_absolute() or ".." in p.parts or "\\" in member.name:
            raise ValueError("Unsafe archive path")
        if not p.parts or p.parts[0] not in ("out", "site-manifest.json"):
            raise ValueError("Unexpected archive root")
        if member.name == "site-manifest.json" and not member.isfile():
            raise ValueError("Invalid manifest")
        if not (member.isfile() or member.isdir()):
            raise ValueError("Links and special files are forbidden")
    source.extractall(destination, members=members, filter="data")
