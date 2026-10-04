// Return one player, refusing ambiguous pages rather than muting unrelated videos.
globalThis.skyboxSelectVideo = function selectVideo(candidates) {
  const visible = candidates.filter((candidate) => candidate.visible);
  const playing = visible.filter((candidate) => candidate.playing);
  const eligible = playing.length > 0 ? playing : visible;
  if (eligible.length === 0) {
    throw new Error("No visible video found. Open the streaming player and try again.");
  }
  if (eligible.length !== 1) {
    throw new Error("More than one visible player found. Keep one player visible and try again.");
  }
  return eligible[0].element;
};
