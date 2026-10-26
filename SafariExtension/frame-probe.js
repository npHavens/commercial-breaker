// One local, downscaled frame. Never change source, CORS mode, DRM, or playback.
(() => {
  let state = {};
  try {
    if (location.protocol !== 'https:' || !['directv.com', 'paramountplus.com'].some(
      (domain) => location.hostname === domain || location.hostname.endsWith(`.${domain}`))) {
      throw new Error('Open DIRECTV or Paramount+ first.');
    }
    const candidates = Array.from(document.querySelectorAll('video'), (element) => {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return { element, playing: !element.paused && !element.ended,
        visible: rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.right > 0 &&
          rect.top < innerHeight && rect.left < innerWidth && style.display !== 'none' &&
          style.visibility === 'visible' && Number(style.opacity) > 0 };
    });
    const video = globalThis.commercialBreakerSelectVideo(candidates);
    state = { wireless: typeof video.webkitCurrentPlaybackTargetIsWireless === 'boolean' ?
      video.webkitCurrentPlaybackTargetIsWireless : null,
      paused: video.paused, readyState: video.readyState,
      currentTime: Number.isFinite(video.currentTime) ? video.currentTime : null,
      width: video.videoWidth, height: video.videoHeight };
    if (video.readyState < 2 || !video.videoWidth || !video.videoHeight) {
      return JSON.stringify({ ok: true, ...state, outcome: 'no-frame' });
    }
    const canvas = document.createElement('canvas');
    canvas.width = 320;
    canvas.height = Math.max(1, Math.min(320, Math.round(320 * video.videoHeight / video.videoWidth)));
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (!context) throw new Error('Canvas context unavailable.');
    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
    let dark = 0;
    let min = 255;
    let max = 0;
    for (let i = 0; i < pixels.length; i += 4) {
      const brightness = Math.max(pixels[i], pixels[i + 1], pixels[i + 2]);
      if (brightness <= 8 || pixels[i + 3] === 0) dark++;
      min = Math.min(min, brightness);
      max = Math.max(max, brightness);
    }
    const darkFraction = dark / (pixels.length / 4);
    return JSON.stringify({ ok: true, ...state,
      outcome: darkFraction >= 0.99 ? 'near-black' : 'pixels-readable',
      darkFraction, brightnessRange: max - min,
      preview: canvas.toDataURL('image/png') });
  } catch (error) {
    return JSON.stringify({ ok: false, ...state,
      outcome: error.name === 'SecurityError' ? 'access-blocked' : 'error',
      error: error.name === 'SecurityError' ? 'Safari blocked pixel readback for this video.' :
        (error.message || 'Frame test failed.') });
  }
})();
