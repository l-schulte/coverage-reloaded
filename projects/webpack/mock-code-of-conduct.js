const fs = require("fs");
const path = require("path");
const http = require("http");
const https = require("https");
const crypto = require("crypto");
const { EventEmitter } = require("events");
const { Readable } = require("stream");

const CACHE_CONTROL = "public, max-age=86400";
const GITHUB_RAW_HOST = "raw.githubusercontent.com";

/**
 * Read a file from the checked-out commit and derive a stable ETag for it.
 *
 * The ETag is not cosmetic: webpack's `HttpUriPlugin` fetches through
 * `proxyFetch(getHttp(), proxy)`, i.e. `https.get(url, { headers }, cb)`, and it
 * builds `{ "if-none-match": cachedResult.etag || undefined }` when revalidating
 * a cached response. Node's HTTP client rejects an `undefined` header value with
 * `ERR_HTTP_INVALID_HEADER_VALUE: Invalid value "undefined" for header
 * "if-none-match"`, so serving an ETag keeps every cached entry revalidatable.
 *
 * There is deliberately no fallback body. webpack's asset-module cases pin an
 * integrity hash per URL in their `*.webpack.lock` files, and the only content
 * that can satisfy it is the one from that commit, so a missing file means the
 * environment is broken: fail loudly instead of serving substituted content that
 * could never match.
 */
function readLocal(localPath) {
  const content = fs.readFileSync(localPath);
  const etag = `"${crypto.createHash("sha1").update(content).digest("hex").slice(0, 32)}"`;
  return { content, etag };
}

/**
 * Map a GitHub raw URL onto a file of the checked-out commit.
 *
 * `https://raw.githubusercontent.com/webpack/webpack/main/README.md` maps to
 * `<repo>/README.md`, exactly like the URL's branch/ref portion is irrelevant to
 * the commit being tested. Returns `null` when the URL is not something we can
 * serve from the checkout (other owners/repos, unknown layouts).
 */
function resolveLocalPath(u) {
  if (!u || u.hostname !== GITHUB_RAW_HOST) return null;
  const segments = u.pathname.replace(/^\/+/, "").split("/");
  if (segments.length < 4) return null;
  const [owner, repo, , ...rest] = segments;
  if (owner !== "webpack" || repo !== "webpack") return null;
  const rel = rest.join("/");
  if (!rel || rel.includes("..")) return null;
  return path.resolve(process.cwd(), rel);
}

function isCodeOfConductUrl(u) {
  return Boolean(u) && /code_of_conduct/i.test(u.pathname);
}

function hook(module) {
  const origGet = module.get;
  const origRequest = module.request;

  function handler(url, options, cb) {
    let u = typeof url === "string" ? new URL(url) : (url instanceof URL ? url : null);
    if (!u && options && options.hostname) {
      const proto = module === https ? "https" : "http";
      u = new URL(`${proto}://${options.hostname}${options.path || "/"}`);
    }
    if (!u) return null;

    const rawGithub = u.hostname === GITHUB_RAW_HOST;
    // Unnormalized double slash: synthesize GitHub's 301 locally, for every raw
    // URL (webpack's asset-module cases import both `//webpack//webpack//...`
    // and the clean form, and expect both to resolve to the same content).
    const needsRedirect = rawGithub && u.pathname.includes("//");

    // Servable from the checkout itself?
    const localPath = resolveLocalPath(u);
    const codeOfConduct = isCodeOfConductUrl(u);
    if (!needsRedirect) {
      if (!localPath && !codeOfConduct) return null;
      if (!codeOfConduct && !fs.existsSync(localPath)) {
        // Unknown paths under webpack/webpack must fall through to the network:
        // several cases assert on real 404s.
        return null;
      }
    }

    {
      const callback = typeof options === "function" ? options : cb;
      const req = new EventEmitter();
      req.setHeader = () => req;
      req.getHeader = () => undefined;
      req.removeHeader = () => req;
      req.write = () => true;
      req.abort = () => {};
      req.destroy = () => {};
      req.end = () => {
        // If unnormalized double slash, simulate GitHub HTTP 301 redirect:
        if (needsRedirect) {
          const cleanPath = u.pathname.replace(/\/\/+/g, "/");
          const redirectUrl = `https://${u.hostname}${cleanPath}`;
          const res = new Readable({
            read() {
              this.push(null);
            }
          });
          res.statusCode = 301;
          res.complete = true;
          res.headers = {
            location: redirectUrl,
            "content-length": "0"
          };
          process.nextTick(() => {
            if (callback) callback(res);
            req.emit("response", res);
          });
          return req;
        }

        // A missing CODE_OF_CONDUCT.md throws here on purpose (no fallback).
        const { content, etag } = readLocal(
          localPath || path.resolve(process.cwd(), "CODE_OF_CONDUCT.md")
        );
        const ifNoneMatch =
          options && typeof options === "object" && options.headers
            ? options.headers["if-none-match"] || options.headers["If-None-Match"]
            : undefined;

        if (ifNoneMatch && ifNoneMatch === etag) {
          const notModified = new Readable({
            read() {
              this.push(null);
            }
          });
          notModified.statusCode = 304;
          notModified.complete = true;
          notModified.headers = { etag, "cache-control": CACHE_CONTROL };
          process.nextTick(() => {
            if (callback) callback(notModified);
            req.emit("response", notModified);
          });
          return req;
        }

        const res = new Readable({
          read() {
            this.push(content);
            this.push(null);
          }
        });
        res.statusCode = 200;
        res.complete = true;
        res.headers = {
          "content-type": "text/plain; charset=utf-8",
          "content-length": String(content.length),
          "cache-control": CACHE_CONTROL,
          etag
        };
        process.nextTick(() => {
          if (callback) callback(res);
          req.emit("response", res);
        });
        return req;
      };
      return req;
    }
    return null;
  }

  module.request = function(url, options, cb) {
    const mock = handler(url, options, cb);
    if (mock) return mock;
    return origRequest.apply(this, arguments);
  };

  module.get = function(url, options, cb) {
    const mock = handler(url, options, cb);
    if (mock) {
      mock.end();
      return mock;
    }
    return origGet.apply(this, arguments);
  };
}

hook(http);
hook(https);
