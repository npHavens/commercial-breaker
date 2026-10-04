// Called only by Skybox's popup in the active tab's isolated extension world.
globalThis.skyboxPlayer = function skyboxPlayer(toggle) {
  try {
    if (location.protocol !== "https:" ||
        !["paramountplus.com", "directv.com"].some((domain) => location.hostname === domain || location.hostname.endsWith(`.${domain}`))) {
      throw new Error("Open a DIRECTV or Paramount+ video, then open Skybox again.");
    }
    const candidates = Array.from(document.querySelectorAll("video"), (element) => {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      const visible = rect.width > 0 && rect.height > 0 &&
        rect.bottom > 0 && rect.right > 0 &&
        rect.top < innerHeight && rect.left < innerWidth &&
        style.visibility === "visible" && style.display !== "none" &&
        Number(style.opacity) > 0;
      return { element, visible, playing: !element.paused && !element.ended };
    });
    const video = globalThis.skyboxSelectVideo(candidates);
    if (toggle) video.muted = !video.muted;
    return { ok: true, muted: video.muted, volume: video.volume, paused: video.paused };
  } catch (error) {
    return { ok: false, error: error.message || "Could not control the player." };
  }
};
