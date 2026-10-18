/**
 * Skybox sends audio only to Vertex AI, the destination its consent text names.
 * Authentication uses Application Default Credentials; there is no API-key mode.
 */
export function vertexConfig(env = process.env) {
  const project = env.GOOGLE_CLOUD_PROJECT?.trim();
  if (!project) throw new Error('configuration-missing');
  // "global" serves current Gemini models; set a region only when required.
  return { vertexai: true, project, location: env.GOOGLE_CLOUD_LOCATION?.trim() || 'global' };
}

/** The SDK loads lazily so offline tests run without installed dependencies. */
export async function createVertexClient(config = vertexConfig()) {
  let GoogleGenAI;
  try { ({ GoogleGenAI } = await import('@google/genai')); }
  catch (error) {
    if (error?.code === 'ERR_MODULE_NOT_FOUND') throw new Error('dependencies-missing');
    throw error;
  }
  return new GoogleGenAI({ ...config, httpOptions: { retryOptions: { attempts: 1 } } });
}

/** Only fixed setup categories leave a worker; messages can contain local paths. */
export function setupFailure(error) {
  return ['configuration-missing', 'dependencies-missing'].includes(error?.message) ? error.message : 'setup-failed';
}
