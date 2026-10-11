// Rend une ou plusieurs scènes JSON (produites par tools/sim) en PNG avec Chromium.
// Usage : node render.mjs scene1.json [scene2.json ...] --out <dossier>
import { chromium } from "/opt/node-tools/node_modules/playwright/index.mjs";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const outIdx = args.indexOf("--out");
const outDir = outIdx >= 0 ? args[outIdx + 1] : path.join(here, "out");
const files = args.filter((a, i) => a !== "--out" && i !== outIdx + 1);
fs.mkdirSync(outDir, { recursive: true });

const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".woff2": "font/woff2", ".woff": "font/woff", ".json": "application/json" };
const server = http.createServer((req, res) => {
  const p = path.join(here, decodeURIComponent(req.url.split("?")[0]));
  if (!p.startsWith(here) || !fs.existsSync(p)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": types[path.extname(p)] || "application/octet-stream" });
  fs.createReadStream(p).pipe(res);
});
await new Promise(r => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
for (const file of files) {
  const scenes = JSON.parse(fs.readFileSync(file, "utf8"));
  for (const scene of Array.isArray(scenes) ? scenes : [scenes]) {
    const page = await browser.newPage({ viewport: { width: scene.width, height: scene.height } });
    page.on("console", m => { if (m.type() === "error") console.error("[page]", m.text()); });
    let failed = null;
    page.on("pageerror", e => { console.error("[pageerror]", scene.name, e.message); failed = e; });
    await page.addInitScript(s => { window.__SCENE__ = s; window.addEventListener("error", () => { window.__FAILED__ = true; }); }, scene);
    await page.goto(`http://127.0.0.1:${port}/page.html`);
    await page.waitForFunction(() => window.__DONE__ === true || window.__FAILED__, null, { timeout: 120000 }).catch(e => { failed = failed || e; });
    if (failed) { console.error("FAILED", scene.name); await page.close(); continue; }
    const out = path.join(outDir, scene.name + ".png");
    await page.locator("#wrap").screenshot({ path: out });
    console.log("rendered", out);
    await page.close();
  }
}
await browser.close();
server.close();
