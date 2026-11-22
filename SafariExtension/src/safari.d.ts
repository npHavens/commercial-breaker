// Safari's non-standard media members that the extension reads or calls. Each is optional, because
// the code checks for it before use and other browsers don't have it.
interface HTMLMediaElement {
  webkitCurrentPlaybackTargetIsWireless?: boolean;
  webkitClosedCaptionsVisible?: boolean;
  webkitShowPlaybackTargetPicker?(): void;
  getStartDate?(): Date;
}
