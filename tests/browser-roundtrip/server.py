import html
import re
import secrets
import sqlite3
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from settings import HOSTS, PORT
from settings import ROOT as root


def db():
    return sqlite3.connect(root / "records.db")


with db() as c:
    c.execute(
        "create table if not exists records(id text primary key, host text, title text, filename text, data blob)"
    )


class App(BaseHTTPRequestHandler):
    def route(self):
        return re.fullmatch(r"/([a-z]+)/([a-z]+)(?:/([a-f0-9]{16}))?", self.path)

    def body(self, b, kind="text/html; charset=utf-8", attachment=False):
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        if attachment:
            self.send_header(
                "Content-Disposition", 'attachment; filename="receipt.txt"'
            )
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        m = self.route()
        if not m or m[1] not in HOSTS:
            return self.send_error(404)
        h, a, i = m.groups()
        if a == "form":
            s = f'<h1>Synthetic file intake</h1><form method="post" enctype="multipart/form-data"><label>Title <input name="title" required></label><label>Attachment <input type="file" name="file" required></label><button>Save record</button></form>'
        elif a == "records":
            with db() as c:
                rows = c.execute(
                    "select id,title from records where host=? order by rowid desc",
                    (h,),
                ).fetchall()
            s = "<h1>Saved records</h1>" + "".join(
                f'<p><a id="r-{html.escape(t.split()[-1], quote=True)}" href="/{h}/record/{k}">{html.escape(t)}</a></p>'
                for k, t in rows
            )
        else:
            with db() as c:
                r = c.execute(
                    "select title,filename,data from records where host=? and id=?",
                    (h, i),
                ).fetchone()
            if not r:
                return self.send_error(404)
            if a == "download":
                return self.body(r[2], "application/octet-stream", True)
            if a != "record":
                return self.send_error(404)
            s = f'<h1>Record {i}</h1><p>{html.escape(r[0])}</p><p>{html.escape(r[1])}</p><a download href="/{h}/download/{i}">Download attachment</a>'
        self.body(
            (
                "<!doctype html><style>body{font:24px system-ui;margin:5vw}label,button{display:block;margin:24px 0}input,button{font:inherit}</style>"
                + s
            ).encode()
        )

    def do_POST(self):
        m = self.route()
        if not m or m[1] not in HOSTS or m[2] != "form":
            return self.send_error(404)
        if self.headers.get("Origin") != f"http://127.0.0.1:{PORT}":
            return self.send_error(403)
        length = self.headers.get("Content-Length", "")
        if not length.isdecimal() or len(length) > 6:
            return self.send_error(400)
        n = int(length)
        if n > 20000:
            return self.send_error(413)
        fields = {
            p.get_param("name", header="content-disposition"): p
            for p in BytesParser(policy=default)
            .parsebytes(
                ("Content-Type: " + self.headers["Content-Type"] + "\r\n\r\n").encode()
                + self.rfile.read(n)
            )
            .iter_parts()
        }
        if set(fields) != {"title", "file"}:
            return self.send_error(400)
        title = (
            fields["title"].get_payload(decode=True).decode("ascii", errors="replace")
        )
        match = re.fullmatch(rf"Portfolio QA {m[1]} ([0-9a-f]{{8}})", title)
        if not match:
            return self.send_error(400)
        file = fields["file"]
        if (
            file.get_filename() != "synthetic.txt"
            or file.get_payload(decode=True)
            != f"Synthetic QA file {m[1]} {match[1]}".encode()
        ):
            return self.send_error(400)
        i = secrets.token_hex(8)
        with db() as c:
            c.execute(
                "insert into records values(?,?,?,?,?)",
                (i, m[1], title, file.get_filename(), file.get_payload(decode=True)),
            )
        self.send_response(303)
        self.send_header("Location", f"/{m[1]}/records")
        self.end_headers()


ThreadingHTTPServer(("127.0.0.1", PORT), App).serve_forever()
