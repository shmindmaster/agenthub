import argparse
import hashlib
import json
import sqlite3

import av
from PIL import ImageChops, ImageStat
from settings import HOSTS
from settings import ROOT as d

parser = argparse.ArgumentParser()
parser.add_argument("--host", choices=sorted(HOSTS), action="append")
expected = set(parser.parse_args().host or HOSTS)
failures = []
db = sqlite3.connect(d / "records.db")
verified = []
for p in sorted(d.glob("*/*/proof.json")):
    if p.parent.parent.name not in expected:
        continue
    try:
        e = json.loads(p.read_text())
        w = p.parent
        h = e["host"]
        rows = db.execute(
            "select id,title,filename,data from records where host=? and title=?",
            (h, e["title"]),
        ).fetchall()
        assert len(rows) == 1 and rows[0][:3] == (
            e["record"],
            e["title"],
            "synthetic.txt",
        )
        data = rows[0][3]
        assert (
            data
            == (w / "download.txt").read_bytes()
            == (w / "synthetic.txt").read_bytes()
            and hashlib.sha256(data).hexdigest() == e["sha256"]
        )
        with av.open(str(w / "flow.mp4")) as media:
            stream = media.streams.video[0]
            codec = stream.codec_context.name
            sz = [stream.width, stream.height]
            frames = 0
            changes = 0
            last = None
            for frame in media.decode(stream):
                im = frame.to_image().convert("L").resize((320, 200))
                if (
                    last is not None
                    and ImageStat.Stat(ImageChops.difference(im, last)).mean[0] > 0.2
                ):
                    changes += 1
                last = im
                frames += 1
            seconds = media.duration / av.time_base
        assert codec == "h264" and frames >= 4 and seconds > 2 and changes >= 2, (
            codec,
            frames,
            seconds,
            changes,
        )
        verified.append(
            dict(
                host=h,
                record=e["record"],
                fileSHA256=e["sha256"],
                downloadVerified=True,
                reopened=True,
                submissionCount=len(rows),
                recording=str(w / "flow.mp4"),
                codec=codec,
                dimensions=sz,
                frames=frames,
                seconds=round(seconds, 2),
                visibleChanges=changes,
            )
        )
    except Exception as exc:
        failures.append(str(p))
        print("FAIL", p, repr(exc))
(d / "verification.json").write_text(json.dumps(verified, indent=2))
print("Verified:", ", ".join(r["host"] for r in verified))

missing = expected - {r["host"] for r in verified}
if missing or failures:
    raise SystemExit(f"Missing hosts: {sorted(missing)}; failed proofs: {failures}")
