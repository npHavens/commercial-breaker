// Pure request validation shared by the background listener and tests.
globalThis.commercialBreakerParamountCapture = {
  paramount(value) {
    try {
      const u = new URL(value);
      return u.protocol === 'https:' && (u.hostname === 'paramountplus.com' || u.hostname.endsWith('.paramountplus.com'));
    } catch { return false; }
  },
  playlist(value) {
    try {
      const u = new URL(value);
      return u.protocol === 'https:' && u.hostname === 'dai.google.com' &&
        !u.username && !u.password && !u.hash && (!u.port || u.port === '443') &&
        /^\/linear\/hls\/pa\/event\/[^/]+\/stream\/[^/]+\/variant\/[^/]+\/bandwidth\/\d+\.m3u8$/.test(u.pathname);
    } catch { return false; }
  },
  key(value) {
    try {
      const u = new URL(value);
      return u.protocol === 'https:' && u.hostname === 'cbsi.live.ott.irdeto.com' &&
        u.pathname === '/key' && !u.username && !u.password && !u.hash && (!u.port || u.port === '443');
    } catch { return false; }
  },
  token(headers = []) {
    const matches = headers.filter(h => h.name.toLowerCase() === 'authorization');
    if (matches.length !== 1) return null;
    const match = /^Bearer ([A-Za-z0-9._~+\/-]+=*)$/i.exec(matches[0].value || '');
    return match && match[1].length <= 16384 ? match[1] : null;
  }
};
