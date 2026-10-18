export const responseSchema = {
  type: 'OBJECT',
  properties: {
    state_at_end: { type: 'STRING', enum: ['program', 'commercial', 'promo', 'unclear'] },
    tv_audibility: { type: 'STRING', enum: ['clear', 'faint', 'unusable'] },
    room_speech_overlap: { type: 'STRING', enum: ['present', 'absent', 'uncertain'] },
    transition_heard: { type: 'BOOLEAN' }, evidence: { type: 'STRING' },
    confidence: { type: 'NUMBER', minimum: 0, maximum: 1 },
  },
  required: ['state_at_end', 'tv_audibility', 'room_speech_overlap', 'transition_heard', 'evidence', 'confidence'],
};

/** Validates provider output without treating model confidence as calibrated truth. */
export function parseResult(text) {
  const value = JSON.parse(text);
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid response object');
  for (const field of ['state_at_end', 'tv_audibility', 'room_speech_overlap']) {
    if (!responseSchema.properties[field].enum.includes(value[field])) throw new Error(`Invalid ${field}`);
  }
  if (typeof value.transition_heard !== 'boolean' || typeof value.evidence !== 'string' || value.evidence.length > 2000
      || !Number.isFinite(value.confidence) || value.confidence < 0 || value.confidence > 1) throw new Error('Invalid response fields');
  return Object.fromEntries(responseSchema.required.map(key => [key, value[key]]));
}
