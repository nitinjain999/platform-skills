'use strict';

/**
 * Lambda@Edge viewer-request handler.
 *
 * Runs at every edge location before the cache is checked.
 * Use cases: lightweight auth, geo-based redirect, A/B routing by cookie.
 *
 * Constraints:
 * - No network calls (no SDK, no fetch, no require('https'))
 * - No environment variables — embed config as constants or use CloudFront KeyValueStore
 * - Max 128 MB memory, 5s timeout
 * - No body access at viewer-request (use origin-request for body)
 */

const BYPASS_PATHS = ['/health', '/favicon.ico'];
const ALLOWED_METHODS = ['GET', 'HEAD', 'OPTIONS'];

exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const headers = request.headers;
  const uri = request.uri;
  const method = request.method;

  // Pass through health checks and static assets without auth
  if (BYPASS_PATHS.some((p) => uri.startsWith(p))) {
    return request;
  }

  // Example: enforce GET/HEAD/OPTIONS only on /api/ paths
  if (uri.startsWith('/api/') && !ALLOWED_METHODS.includes(method)) {
    return {
      status: '405',
      statusDescription: 'Method Not Allowed',
      headers: {
        allow: [{ key: 'Allow', value: ALLOWED_METHODS.join(', ') }],
        'cache-control': [{ key: 'Cache-Control', value: 'no-store' }],
      },
    };
  }

  // Example: require Authorization header on /api/ (validate signature inline — no network)
  if (uri.startsWith('/api/')) {
    const authHeader = headers['authorization'];
    if (!authHeader || !authHeader[0].value.startsWith('Bearer ')) {
      return {
        status: '401',
        statusDescription: 'Unauthorized',
        headers: {
          'www-authenticate': [{ key: 'WWW-Authenticate', value: 'Bearer realm="api"' }],
          'cache-control': [{ key: 'Cache-Control', value: 'no-store' }],
        },
      };
    }
    // Validate the JWT signature here using the crypto module (available in Lambda@Edge)
    // Never make network calls to a token endpoint — validate locally using a cached public key
  }

  // Example: A/B routing by cookie — send 20% of traffic to /v2/ origin path
  const abCookie = headers['cookie']
    ? headers['cookie'][0].value.split(';').find((c) => c.trim().startsWith('ab='))
    : null;

  if (!abCookie) {
    const bucket = Math.random() < 0.2 ? 'b' : 'a';
    // Set cookie so the same user gets the same bucket on subsequent requests
    request.headers['set-cookie'] = [
      { key: 'Set-Cookie', value: `ab=${bucket}; Path=/; Max-Age=86400; SameSite=Lax` },
    ];
    if (bucket === 'b') {
      request.uri = '/v2' + uri;
    }
  }

  return request;
};
