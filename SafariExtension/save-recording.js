(() => {
  const key = 'skybox.recording-export';
  const message = document.querySelector('#message');
  try {
    const raw = localStorage.getItem(key);
    if (!raw) throw new Error('No recording is stored. Export a recording from Skybox first.');
    const saved = JSON.parse(raw);
    if (typeof saved.json !== 'string') {
      throw new Error('The stored recording is invalid.');
    }
    globalThis.skyboxValidateExport(saved.json);
    const blob = new Blob([saved.json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const download = document.querySelector('#download');
    download.href = url;
    download.download = saved.filename;
    download.hidden = false;
    const open = document.querySelector('#open');
    open.href = url;
    open.hidden = false;
    message.textContent = `${saved.filename} · ${blob.size.toLocaleString()} bytes ready to save.`;
    const clear = document.querySelector('#clear');
    clear.disabled = false;
    clear.addEventListener('click', () => {
      // Do not erase a newer export opened in another tab.
      if (localStorage.getItem(key) === raw) localStorage.removeItem(key);
      clear.disabled = true;
      message.textContent = 'Recovery copy cleared. This tab’s download remains available until you close it.';
    });
    // The browser releases the URL when this document closes. Early revocation
    // would interrupt downloads or the separately opened JSON tab.
  } catch (error) {
    message.textContent = error.message || 'Could not load the recording.';
  }
})();
