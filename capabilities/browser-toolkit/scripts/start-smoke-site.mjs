import { createServer } from "node:http";
import { readFile } from "node:fs/promises";

const host = "127.0.0.1";
const port = Number(process.env.BROWSER_TOOLKIT_SMOKE_PORT || 41731);
const page = await readFile(new URL("../fixtures/browser-smoke/index.html", import.meta.url));

const server = createServer((request, response) => {
  response.setHeader("Cache-Control", "no-store");
  if (request.method === "GET" && request.url === "/") {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    response.end(page);
    return;
  }
  if (request.method === "POST" && request.url === "/api/submit") {
    let body = "";
    request.on("data", chunk => { body += chunk; });
    request.on("end", () => {
      const data = JSON.parse(body || "{}");
      response.writeHead(200, { "Content-Type": "application/json" });
      response.end(JSON.stringify({ ok: true, name: String(data.name || "") }));
    });
    return;
  }
  response.writeHead(404, { "Content-Type": "application/json" });
  response.end(JSON.stringify({ error: "not found" }));
});

server.listen(port, host, () => {
  console.log(`BROWSER_TOOLKIT_SMOKE_READY http://${host}:${port}`);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
