/**
 * Inference Gateway — API Key Proxy
 * Agjentët lidhen këtu pa API keys, gateway shton key-in dhe forwardon.
 * Providers: Anthropic (Claude), Google (Gemini), Moonshot (Kimi)
 */
const http = require("http");
const https = require("https");
const url = require("url");

const PORT = parseInt(process.env.INFERENCE_PORT || "18792");
const GATEWAY_SECRET = process.env.INFERENCE_GATEWAY_SECRET || "";

const PROVIDERS = {
    anthropic: {
        host: "api.anthropic.com",
        basePath: "/v1",
        authHeader: "x-api-key",
        key: process.env.ANTHROPIC_API_KEY,
        extraHeaders: { "anthropic-version": "2023-06-01" }
    },
    google: {
        host: "generativelanguage.googleapis.com",
        basePath: "/v1beta",
        authHeader: null,
        key: process.env.GOOGLE_AI_API_KEY,
        keyInQuery: true
    },
    moonshot: {
        host: "api.moonshot.ai",
        basePath: "/v1",
        authHeader: "Authorization",
        key: process.env.MOONSHOT_API_KEY,
        authPrefix: "Bearer "
    }
};

function proxyRequest(provider, reqPath, method, headers, body, res) {
    const p = PROVIDERS[provider];
    if (!p) {
        res.writeHead(400, { "Content-Type": "application/json" });
        return res.end(JSON.stringify({ error: `Unknown provider: ${provider}` }));
    }
    if (!p.key) {
        res.writeHead(503, { "Content-Type": "application/json" });
        return res.end(JSON.stringify({ error: `No API key for ${provider}` }));
    }

    const outHeaders = {
        "Content-Type": "application/json",
        ...p.extraHeaders
    };

    if (p.authHeader) {
        outHeaders[p.authHeader] = (p.authPrefix || "") + p.key;
    }

    let fullPath = p.basePath + reqPath;
    if (p.keyInQuery) {
        fullPath += (fullPath.includes("?") ? "&" : "?") + `key=${p.key}`;
    }

    const options = {
        hostname: p.host,
        port: 443,
        path: fullPath,
        method: method,
        headers: outHeaders
    };

    if (body) {
        options.headers["Content-Length"] = Buffer.byteLength(body);
    }

    const proxyReq = https.request(options, (proxyRes) => {
        res.writeHead(proxyRes.statusCode, {
            "Content-Type": proxyRes.headers["content-type"] || "application/json"
        });
        proxyRes.pipe(res);
    });

    proxyReq.on("error", (err) => {
        console.error(`[Gateway] ${provider} error:`, err.message);
        res.writeHead(502, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: `Provider error: ${err.message}` }));
    });

    if (body) proxyReq.write(body);
    proxyReq.end();
}

const server = http.createServer((req, res) => {
    // Health check
    if (req.url === "/health") {
        res.writeHead(200, { "Content-Type": "application/json" });
        return res.end(JSON.stringify({
            ok: true,
            providers: Object.keys(PROVIDERS).filter(p => PROVIDERS[p].key)
        }));
    }

    // Auth check
    if (GATEWAY_SECRET) {
        const token = (req.headers["authorization"] || "").replace("Bearer ", "");
        if (token !== GATEWAY_SECRET) {
            res.writeHead(401, { "Content-Type": "application/json" });
            return res.end(JSON.stringify({ error: "Unauthorized" }));
        }
    }

    // Route: /provider/path — e.g. /anthropic/messages, /moonshot/chat/completions
    const parsed = url.parse(req.url);
    const parts = parsed.pathname.split("/").filter(Boolean);
    const provider = parts[0];
    const reqPath = "/" + parts.slice(1).join("/") + (parsed.search || "");

    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", () => {
        console.log(`[Gateway] ${req.method} /${provider}${reqPath} (${body.length}b)`);
        proxyRequest(provider, reqPath, req.method, req.headers, body, res);
    });
});

server.listen(PORT, "0.0.0.0", () => {
    const active = Object.keys(PROVIDERS).filter(p => PROVIDERS[p].key);
    console.log(`[Inference Gateway] Port ${PORT} | Providers: ${active.join(", ")}`);
});
