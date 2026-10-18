/** Only the blind ID, prompt, and audio enter the request; marker labels stay local. */
export function makeContents(sampleId, prompt, audio) {
  if (!/^[a-f0-9]{12}$/.test(sampleId) || !Buffer.isBuffer(audio) || audio.length === 0) throw new Error('Invalid sample input');
  return [{ role: 'user', parts: [{ text: `${prompt}\nBlind sample ID: ${sampleId}` },
    { inlineData: { mimeType: 'audio/wav', data: audio.toString('base64') } }] }];
}
