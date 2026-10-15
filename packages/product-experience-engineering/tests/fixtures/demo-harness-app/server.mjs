// Fixture service for demo-stack tests: health, version and a page with the synthetic label.
import { createServer } from "node:http";
const port = Number(process.env.DEMO_PORT ?? 47613);
createServer((req, res) => {
  if (req.url === "/health") return res.end("ok");
  if (req.url === "/api/version") {
    res.setHeader("content-type", "application/json");
    return res.end(JSON.stringify({ schema: "deployed-version/v1", service: "fixture-api", gitSha: "unknown", environment: "local" }));
  }
  res.setHeader("content-type", "text/html");
  res.end('<span data-testid="synthetic-data-label">Synthetic demo data</span>');
}).listen(port, "127.0.0.1");
