// Exercise (Nick): declare the page globals the extension's scripts share, and the messages the
// popup sends the background script. Until this file declares them, `npx tsc -p SafariExtension
// --noEmit` lists every place that needs one (TS7017 on globalThis, and the panel's untyped video).
//
// Each global is set by one script and read by another:
// - commercialBreakerSelectVideo: set in select-video.ts, called by player.ts and airplay-session.ts
// - commercialBreakerPlayer: set in player.ts, called by the popup through executeScript
// - commercialBreakerAirPlayPanel: set in airplay-session.ts, checked by the popup and the panel
// - commercialBreakerAirPlayRouteResult: set in airplay-session.ts after a route test
// - commercialBreakerDirectvRecovery: set in directv-airplay-recovery.ts, which also checks it
// - commercialBreakerIsRelayUrl: set in relay-target.ts, used by background.ts and the popup
// - commercialBreakerParamountCapture: set in paramount-capture.ts, used by background.ts
//
// Messages: the popup sends { type: 'paramount-status' } or { type: 'paramount-capture', tabId,
// code }, and background.ts answers with { message } or { message, capturing }.
//
// The emitted JavaScript must not change: the migration's token check compares dist/ with main.
