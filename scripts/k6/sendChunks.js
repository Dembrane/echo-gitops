import { sleep, group } from 'k6'
import http from 'k6/http'

// Minimal configuration
const PROJECT_ID = __ENV.PROJECT_ID
const API_BASE = 'https://api.dembrane.com'
const CHUNKS_DIR = __ENV.CHUNKS_DIR || 'audioChunks'
const START = Number(__ENV.START || 0)
const END = Number(__ENV.END || 3)
const SLEEP_SEC = Number(__ENV.SLEEP || 30)
const CALL_FINISH = ((__ENV.CALL_FINISH || 'true') + '').toLowerCase() === 'true'
const CHUNK_FIELD = 'chunk'

export const options = {
  scenarios: {
    default: {
      executor: 'shared-iterations',
      vus: Number(__ENV.VUS || 10),
      iterations: Number(__ENV.ITERATIONS || 10),
      maxDuration: __ENV.MAX_DURATION || '20m',
      gracefulStop: '30s',
    },
  },
}

function zeroPad(num, width) {
  const s = String(num)
  if (s.length >= width) return s
  return '0'.repeat(width - s.length) + s
}

function buildChunkList() {
  const candidates = []
  for (let i = START; i <= END; i++) {
    const idx = zeroPad(i, 3)
    candidates.push(`${CHUNKS_DIR}/chunk_${idx}.webm`)
  }

  const chunks = []
  for (let i = 0; i < candidates.length; i++) {
    const path = candidates[i]
    try {
      const data = open(path, 'b')
      const filename = path.split('/').pop() || `chunk-${i}.webm`
      chunks.push({ data, filename })
    } catch (e) {
      // Skip missing files
    }
  }
  return chunks
}

// Build chunks in init context (required by k6)
const CHUNKS = buildChunkList()

function initiateConversation() {
  const url = `${API_BASE}/api/participant/projects/${PROJECT_ID}/conversations/initiate`
  const body = JSON.stringify({
    name: 'k6 User Talks',
    pin: '',
    tag_id_list: [],
    user_agent:
      'k6/0.x (load test script)',
    source: 'PORTAL_AUDIO',
  })

  const res = http.post(url, body, {
    headers: {
      accept: 'application/json, text/plain, */*',
      'content-type': 'application/json',
    },
  })

  let conversationId = null
  try {
    const json = res.json()
    conversationId = json?.conversation_id || json?.conversation?.id || json?.id || null
  } catch (_) {
    // no-op
  }
  return { res, conversationId }
}

function uploadChunk(conversationId, chunkData, filename, isLast) {
  const url = `${API_BASE}/api/participant/conversations/${conversationId}/upload-chunk`
  const formData = {}
  formData[CHUNK_FIELD] = http.file(chunkData, filename, 'audio/webm')
  formData['timestamp'] = new Date().toISOString()
  formData['source'] = 'PORTAL_AUDIO'
  formData['run_finish_hook'] = String(Boolean(isLast))

  return http.post(url, formData, {
    headers: {
      accept: 'application/json, text/plain, */*',
      // Do NOT set content-type; k6 will set proper multipart boundary
    },
    tags: { name: 'upload_chunk' },
  })
}

function finishConversation(conversationId) {
  const url = `${API_BASE}/api/participant/conversations/${conversationId}/finish`
  return http.post(url, null, {
    headers: {
      accept: 'application/json, text/plain, */*',
    },
  })
}

export default function main() {
  if (!PROJECT_ID) {
    return
  }

  if (!CHUNKS.length) {
    return
  }

  const init = initiateConversation()
  const conversationId = init.conversationId
  if (!conversationId) {
    return
  }

  for (let i = 0; i < CHUNKS.length; i++) {
    const { data, filename } = CHUNKS[i]
    const isLast = i === CHUNKS.length - 1
    uploadChunk(conversationId, data, filename, isLast)
    if (!isLast) {
      sleep(SLEEP_SEC)
    }
  }

  if (CALL_FINISH) {
    finishConversation(conversationId)
  }
}


