(() => {
  const choose = document.querySelector('#choose');
  const capture = document.querySelector('#capture');
  const stopButton = document.querySelector('#stop');
  const message = document.querySelector('#message');
  const preview = document.querySelector('#preview');
  const still = document.querySelector('#still');
  const download = document.querySelector('#download');
  let stream = null;
  let timer = null;
  let pending = false;
  let disposed = false;
  let generation = 0;
  function stop() {
    generation++;
    if (timer !== null) clearTimeout(timer);
    timer = null;
    const previous = stream;
    stream = null;
    if (previous) previous.getTracks().forEach((track) => track.stop());
    preview.srcObject = null;
    capture.disabled = stopButton.disabled = true;
    choose.disabled = pending || disposed;
  }
  choose.addEventListener('click', async () => {
    if (pending || stream || disposed) return;
    if (!navigator.mediaDevices?.getDisplayMedia) {
      message.textContent = 'Screen capture is unavailable on this page in Safari.';
      return;
    }
    pending = true;
    choose.disabled = true;
    still.hidden = download.hidden = true;
    message.textContent = 'Choose the DIRECTV window in Safari’s sharing picker.';
    const attempt = ++generation;
    try {
      // Must run directly from this button's gesture, before any other await.
      const acquired = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
      if (disposed || attempt !== generation) {
        acquired.getTracks().forEach((track) => track.stop());
        return;
      }
      stream = acquired;
      for (const track of stream.getTracks()) track.addEventListener('ended', () => {
        if (stream !== acquired) return;
        stop();
        message.textContent = 'Sharing ended.';
      });
      stopButton.disabled = false;
      timer = setTimeout(() => {
        stop();
        message.textContent = 'Sharing stopped after the 30-second test limit.';
      }, 30000);
      preview.srcObject = stream;
      await preview.play();
      if (stream === acquired) message.textContent = 'Check the live preview, then click Capture frame and stop.';
    } catch (error) {
      stop();
      message.textContent = `Screen capture did not start: ${error.name || 'Error'} — ${error.message || 'No permission or source available.'}`;
    } finally {
      pending = false;
      choose.disabled = !!stream || disposed;
    }
  });
  preview.addEventListener('loadeddata', () => {
    capture.disabled = !stream || preview.readyState < 2;
  });
  capture.addEventListener('click', () => {
    if (!stream || preview.readyState < 2 || !preview.videoWidth || !preview.videoHeight) {
      message.textContent = 'No captured frame is ready yet.';
      return;
    }
    try {
      const canvas = document.createElement('canvas');
      const scale = Math.min(1, 960 / preview.videoWidth, 960 / preview.videoHeight);
      canvas.width = Math.max(1, Math.round(preview.videoWidth * scale));
      canvas.height = Math.max(1, Math.round(preview.videoHeight * scale));
      const context = canvas.getContext('2d');
      if (!context) throw new Error('Canvas is unavailable.');
      context.drawImage(preview, 0, 0, canvas.width, canvas.height);
      context.getImageData(0, 0, 1, 1);
      const image = canvas.toDataURL('image/png');
      still.src = download.href = image;
      download.download = `skybox-screen-${new Date().toISOString().replace(/[:.]/g, '-')}.png`;
      still.hidden = download.hidden = false;
      message.textContent = 'Snapshot captured; sharing stopped. Does the video area show the current game, a black rectangle, or an AirPlay placeholder?';
    } catch (error) {
      message.textContent = `Frame read failed: ${error.name || 'Error'} — ${error.message}`;
    } finally { stop(); }
  });
  stopButton.addEventListener('click', () => { stop(); message.textContent = 'Sharing stopped.'; });
  window.addEventListener('pagehide', () => { disposed = true; stop(); });
})();
