"""Offline tests for wda_client: a loopback stand-in for the runner. No phone, no network."""
import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "skills", "mobile-device-lab", "scripts"))
import wda_client  # noqa: E402

SOURCE = """ Application, 0x1, {{0.0, 0.0}, {393.0, 852.0}}, label: 'Demo'
   Button, 0x2, {{16.0, 60.0}, {44.0, 44.0}}, label: 'Back'
   Cell, 0x3, {{0.0, 900.0}, {393.0, 60.0}}, label: 'Account one 123 456'
   Other, 0x4, {{0.0, 0.0}, {10.0, 10.0}}
"""


class Runner(BaseHTTPRequestHandler):
    log = []
    field = {"value": ""}
    rect_y = [900.0]
    typing_drops = False

    def _send(self, value, status=200):
        body = json.dumps({"value": value}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length)) if length else None

    def do_GET(self):
        Runner.log.append(("GET", self.path, None))
        if self.path.endswith("/source?format=description"):
            return self._send(SOURCE)
        if self.path.endswith("/rect"):
            return self._send({"x": 0, "y": Runner.rect_y[0], "width": 393, "height": 60})
        if self.path.endswith("/attribute/value"):
            return self._send(Runner.field["value"])
        return self._send({"error": "unknown command"}, 404)

    def do_POST(self):
        body = self._body()
        Runner.log.append(("POST", self.path, body))
        if self.path.endswith("/elements"):
            xpath = body["value"]
            if body["using"] in ("predicate string", "class chain"):
                return self._send([{"ELEMENT": f"{body['using'][0]}-1"}] if "General" in xpath else [])
            if "Back" in xpath:
                return self._send([{"ELEMENT": "back-1"}])
            if "ambiguous" in xpath:
                return self._send([{"ELEMENT": "a"}, {"ELEMENT": "b"}])
            if "row" in xpath:
                return self._send([{"ELEMENT": "row-1"}])
            return self._send([])
        if self.path.endswith("/clear"):
            Runner.field["value"] = ""
            return self._send(None)
        if self.path.endswith("/wda/keys"):
            typed = "".join(body["value"])
            Runner.field["value"] = typed[:-1] if Runner.typing_drops else typed
            return self._send(None)
        if self.path.endswith("/wda/dragfromtoforduration"):
            Runner.rect_y[0] -= 300.0
            return self._send(None)
        return self._send(None)

    def log_message(self, *args):
        pass


class WdaClient(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), Runner)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        Runner.log.clear()
        Runner.field["value"] = ""
        Runner.rect_y[0] = 900.0
        Runner.typing_drops = False
        self.wda = wda_client.Wda("S1", base=self.base, mask=r"\d{3} ?\d{3}(?!\d)")

    def test_every_call_goes_under_the_session(self):
        self.wda.tap(10, 20)
        self.assertEqual(Runner.log[-1], ("POST", "/session/S1/wda/tap", {"x": 10, "y": 20}))
        self.wda.keys("ab")
        self.assertEqual(Runner.log[-1][2], {"value": ["a", "b"]})

    def test_screen_parses_rows_and_masks_secrets(self):
        rows = self.wda.screen()
        self.assertEqual([r[0] for r in rows], ["Application", "Button", "Cell"])
        self.assertEqual(rows[2][5], "Account one [masked]")
        self.assertEqual(rows[2][2], 900.0)

    def test_one_refuses_an_ambiguous_or_empty_match(self):
        self.assertIsNone(self.wda.one("//ambiguous"))
        self.assertIsNone(self.wda.one("//nothing"))
        self.assertEqual(self.wda.one("//row"), "row-1")

    def test_predicate_and_class_chain_locators_send_their_own_strategy(self):
        self.assertEqual(self.wda.one_predicate("label == 'General'"), "p-1")
        self.assertEqual(self.wda.one_class_chain("**/XCUIElementTypeCell[`label == 'General'`]"), "c-1")
        self.assertIsNone(self.wda.one_predicate("label == 'Nothing'"))
        usings = [body["using"] for method, path, body in Runner.log if path.endswith("/elements")]
        self.assertEqual(usings, ["predicate string", "class chain", "predicate string"])
        self.assertEqual(self.wda.find("//row"), ["row-1"])
        self.assertEqual(Runner.log[-1][2]["using"], "xpath")

    def test_back_matches_a_real_back_button(self):
        self.assertTrue(self.wda.back(settle=0))
        xpath = next(body["value"] for method, path, body in Runner.log if path.endswith("/elements"))
        self.assertIn("[@label='Back']", xpath)
        self.assertEqual(Runner.log[-1][1], "/session/S1/element/back-1/click")

    def test_type_checked_reports_a_dropped_character(self):
        self.assertTrue(self.wda.type_checked("f1", "Work email", settle=0))
        Runner.typing_drops = True
        self.assertFalse(self.wda.type_checked("f1", "Work email", settle=0))

    def test_bring_into_view_scrolls_with_short_drags(self):
        self.assertEqual(self.wda.bring_into_view("//row", settle=0), "row-1")
        drags = [body for method, path, body in Runner.log if path.endswith("dragfromtoforduration")]
        self.assertEqual(len(drags), 1)
        self.assertIsNone(self.wda.bring_into_view("//ambiguous", settle=0))

    def test_errors_come_back_as_values_and_only_localhost_is_allowed(self):
        self.assertIn("error", self.wda.attr("f1", "label"))
        dead = wda_client.Wda("S1", base="http://127.0.0.1:9")
        self.assertIn("error", dead.call("GET", "/source", timeout=2))
        self.assertEqual(dead.screen(), [])
        with self.assertRaises(ValueError):
            wda_client.Wda("S1", base="http://10.0.0.5:8100")


if __name__ == "__main__":
    unittest.main()
