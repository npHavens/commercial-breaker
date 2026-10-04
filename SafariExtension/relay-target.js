globalThis.skyboxIsRelayUrl = function isRelayUrl(value) {
  try {
    const url = new URL(value);
    const octets = url.hostname.split('.').map(Number);
    const privateHost = octets.length === 4 && octets.every((part) => Number.isInteger(part) && part >= 0 && part <= 255) &&
      (octets[0] === 10 || (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
       (octets[0] === 192 && octets[1] === 168));
    return url.protocol === 'http:' && privateHost && !url.username && !url.password &&
      !url.search && /^\/session\/[A-Za-z0-9_-]{43}\/$/.test(url.pathname);
  } catch { return false; }
};
