globalThis.skyboxRelayControl = function relayControl(command = 'status') {
  try {
    if (!globalThis.skyboxIsRelayUrl(location.href) ||
        document.querySelector('meta[name="skybox-relay"]')?.content !== '1') {
      throw new Error('Open the Skybox relay player in this tab.');
    }
    const output = document.querySelector('#skybox-commercial-state');
    if (!output) throw new Error('Restart the updated relay and refresh its player page.');
    const buttons = { 'toggle-auto': '#skybox-auto-toggle', 'toggle-mute': '#mute' };
    if (command !== 'status') {
      if (!buttons[command]) throw new Error('Unknown relay control.');
      const button = document.querySelector(buttons[command]);
      if (!button) throw new Error('Relay control is unavailable.');
      button.click();
    }
    const state = JSON.parse(output.textContent);
    const video = document.querySelector('#video');
    if (!video || typeof state.enabled !== 'boolean' || typeof state.muted !== 'boolean') {
      throw new Error('The commercial controller is not ready. Restart the updated relay and refresh its player page.');
    }
    return { ok: true, enabled: state.enabled, state: state.state, message: state.message,
      muted: video.muted, paused: video.paused, wireless: Boolean(video.webkitCurrentPlaybackTargetIsWireless) };
  } catch (error) {
    return { ok: false, error: error.message || 'Could not control the relay.' };
  }
};
