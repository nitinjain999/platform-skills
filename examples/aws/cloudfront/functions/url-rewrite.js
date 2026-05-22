// CloudFront Function — viewer-request
// Runtime: cloudfront-js-2.0 (ES5.1 + partial ES6-12, no Node.js modules, no network)
// Execution budget: 1ms, 2MB memory
// Use for: URL rewrites, simple redirects, header manipulation
// NOT for: auth (use Lambda@Edge), network calls (not supported in either)

function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // ── Trailing slash normalisation ──────────────────────────────────────────
  // /about/ → /about/index.html (S3 static site)
  if (uri.endsWith('/')) {
    request.uri = uri + 'index.html';
    return request;
  }

  // ── SPA deep-link rewrite ─────────────────────────────────────────────────
  // Paths without a file extension route to /index.html for client-side routing
  if (!uri.includes('.')) {
    request.uri = '/index.html';
    return request;
  }

  // ── Clean URL rewrite ─────────────────────────────────────────────────────
  // /product/123 → /product?id=123
  var productMatch = uri.match(/^\/product\/(\d+)$/);
  if (productMatch) {
    request.uri = '/product';
    request.querystring = { id: { value: productMatch[1] } };
    return request;
  }

  // ── Security: block path traversal attempts ───────────────────────────────
  if (uri.includes('..') || uri.includes('%2e%2e') || uri.includes('%2E%2E')) {
    return {
      statusCode: 400,
      statusDescription: 'Bad Request',
    };
  }

  return request;
}
