"""Thin WebDriverAgent client for an iPhone over a forwarded port.

Read references/physical-iphone.md first: it has the rules (lease, app locks,
verify before every write, mask secrets) and the commands that start the
runner, forward the port and open a session.

    pymobiledevice3 developer dvt xcuitest <xctrunner bundle id>   # start the runner, keep it running
    pymobiledevice3 usbmux forward 8100 8100                       # localhost only
    pymobiledevice3 developer wda launch <app bundle id>           # prints the session id

    from wda_client import Wda
    wda = Wda(session_id, mask=r"\\d{3} ?\\d{3}(?!\\d)")   # mask one-time codes in anything read
    for kind, x, y, w, h, label in wda.screen(): ...

Coordinates are points, not screenshot pixels. Standard library only.
"""
import json
import re
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8100"
_ROW = re.compile(r"\s*(\w+), 0x\w+, \{\{(-?[\d.]+), (-?[\d.]+)\}, \{([\d.]+), ([\d.]+)\}\}.*?label: '(.*)'")


class Wda:
    def __init__(self, session_id, base=BASE, mask=None):
        if not base.startswith(("http://127.0.0.1:", "http://localhost:")):
            raise ValueError("WebDriverAgent endpoints are unauthenticated: use the localhost forward only")
        self.sid, self.base = session_id, base
        # Optional regex for secrets that must never reach a log.
        self.mask = re.compile(mask) if mask else None

    def call(self, method, path, body=None, timeout=40):
        """One request under this session. Returns the value, or {"error": ...}; it does not raise on a WDA error."""
        req = urllib.request.Request(
            f"{self.base}/session/{self.sid}{path}", method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as response:
                return json.loads(response.read())["value"]
        except urllib.error.HTTPError as error:
            try:
                return {"error": json.loads(error.read()).get("value", {}).get("error", str(error))}
            except (ValueError, AttributeError):
                return {"error": str(error)}
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            return {"error": f"no answer from the runner: {error}"}

    def find(self, locator, using="xpath"):
        """Element ids for a locator. `using` is "xpath", "predicate string" or "class chain"."""
        value = self.call("POST", "/elements", {"using": using, "value": locator})
        return [e["ELEMENT"] for e in value] if isinstance(value, list) else []

    def one(self, locator, using="xpath"):
        """The single matching element, or None. Never act on an ambiguous match."""
        found = self.find(locator, using)
        return found[0] if len(found) == 1 else None

    def one_predicate(self, predicate):
        """The single element matching an NSPredicate such as "label == 'General' AND type == 'XCUIElementTypeCell'".

        Prefer this to XPath and to coordinates on long lists and on screens whose layout shifts when
        text wraps: it is evaluated on the device, and the click goes to the element, not to a point.
        """
        return self.one(predicate, using="predicate string")

    def one_class_chain(self, chain):
        """The single element matching a class chain such as "**/XCUIElementTypeCell[`label == 'General'`]"."""
        return self.one(chain, using="class chain")

    def click(self, el):
        return self.call("POST", f"/element/{el}/click")

    def rect(self, el):
        return self.call("GET", f"/element/{el}/rect")

    def attr(self, el, name):
        return self.call("GET", f"/element/{el}/attribute/{name}")

    def clear(self, el):
        return self.call("POST", f"/element/{el}/clear")

    def tap(self, x, y):
        return self.call("POST", "/wda/tap", {"x": x, "y": y})

    def keys(self, text):
        return self.call("POST", "/wda/keys", {"value": list(text)})

    def drag(self, x1, y1, x2, y2, hold=0.5):
        return self.call("POST", "/wda/dragfromtoforduration",
                         {"fromX": x1, "fromY": y1, "toX": x2, "toY": y2, "duration": hold})

    def screen(self):
        """Every labelled element as (type, x, y, w, h, label), off-screen rows included. About 2 s."""
        source = self.call("GET", "/source?format=description")
        if not isinstance(source, str):
            return []
        rows = []
        for line in source.splitlines():
            match = _ROW.match(line)
            if match:
                kind, x, y, w, h, label = match.groups()
                rows.append((kind, float(x), float(y), float(w), float(h),
                             self.mask.sub("[masked]", label) if self.mask else label))
        return rows

    def back(self, settle=1.2):
        """Go back only if a real Back button exists; a root screen's first navigation button may be a menu."""
        el = self.one("//XCUIElementTypeNavigationBar/XCUIElementTypeButton[@label='Back']")
        if el:
            self.click(el)
            time.sleep(settle)
        return bool(el)

    def type_checked(self, field_el, text, settle=0.5):
        """Replace a field's text and report whether it reads back exactly. Save only when True."""
        self.clear(field_el)
        time.sleep(settle)
        self.keys(text)
        time.sleep(settle)
        return self.attr(field_el, "value") == text

    def bring_into_view(self, xpath, top=80, bottom=700, x=150, tries=14, settle=0.9):
        """Scroll with short drags until the one matching element sits between top and bottom."""
        for _ in range(tries):
            el = self.one(xpath)
            if el is None:
                return None
            rect = self.rect(el)
            if not isinstance(rect, dict) or "y" not in rect:
                return None
            y = rect["y"]
            if top < y < bottom:
                return el
            if y >= bottom:
                self.drag(x, 600, x, 300)
            else:
                self.drag(x, 300, x, 560)
            time.sleep(settle)
        return None
