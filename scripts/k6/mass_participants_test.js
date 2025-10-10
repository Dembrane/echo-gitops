import { sleep } from 'k6'
import http from 'k6/http'
import { FormData } from 'https://jslib.k6.io/formdata/0.0.2/index.js'

const PROJECT_ID = __ENV.PROJECT_ID || '8cda68d1-051b-43b3-b0ad-12fb7eaf58a2'
const API_BASE = 'https://api.echo-next.dembrane.com'
const CHUNKS_DIR = __ENV.CHUNKS_DIR || 'audioChunks'
const SLEEP_SEC = Number(__ENV.SLEEP || 30)
const THINK_TIME = Number(__ENV.THINK_TIME || 30)
const MIN_CHUNKS = Number(__ENV.MIN_CHUNKS || 4)
const MAX_CHUNKS = Number(__ENV.MAX_CHUNKS || 10)

const MAX_VUS = Number(__ENV.VUS || 10)
const DURATION_MINUTES = Number(__ENV.DURATION || 10)
const DURATION_SECONDS = DURATION_MINUTES * 60

// Calculate ramping stages based on duration
const stage1Duration = Math.floor(DURATION_SECONDS * 0.1)  // 0-10%: 25% VUs
const stage2Duration = Math.floor(DURATION_SECONDS * 0.1)  // 10-20%: 50% VUs
const stage3Duration = Math.floor(DURATION_SECONDS * 0.1)  // 20-30%: 100% VUs
const stage4Duration = DURATION_SECONDS - stage1Duration - stage2Duration - stage3Duration  // 30-100%: maintain 100% VUs

export const options = {
  scenarios: {
    ramping_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: `${stage1Duration}s`, target: Math.ceil(MAX_VUS * 0.25) }, // Ramp to 25%
        { duration: `${stage2Duration}s`, target: Math.ceil(MAX_VUS * 0.5) },  // Ramp to 50%
        { duration: `${stage3Duration}s`, target: MAX_VUS },                    // Ramp to 100%
        { duration: `${stage4Duration}s`, target: MAX_VUS },                    // Maintain 100%
      ],
      gracefulRampDown: '30s',
    },
  },
}

function zeroPad(num, width) {
  const s = String(num)
  if (s.length >= width) return s
  return '0'.repeat(width - s.length) + s
}

function loadAllChunks() {
  const chunks = []
  for (let i = 0; i <= 25; i++) {
    const idx = zeroPad(i, 3)
    const path = `${CHUNKS_DIR}/chunk_${idx}.webm`
    try {
      const data = open(path, 'b')
      const filename = `chunk_${idx}.webm`
      chunks.push({ data, filename })
    } catch (e) {
      // Skip missing chunks
    }
  }
  return chunks
}

// Load all available chunks once at init
const ALL_CHUNKS = loadAllChunks()

function getRandomChunkRange() {
  // Ensure we have enough chunks
  if (ALL_CHUNKS.length < MIN_CHUNKS) {
    console.error(`Not enough chunks available. Found ${ALL_CHUNKS.length}, need at least ${MIN_CHUNKS}`)
    return { start: 0, count: ALL_CHUNKS.length }
  }

  // Determine how many chunks this conversation will use
  const maxPossible = Math.min(MAX_CHUNKS, ALL_CHUNKS.length)
  const chunkCount = Math.floor(Math.random() * (maxPossible - MIN_CHUNKS + 1)) + MIN_CHUNKS
  
  // Pick a random starting point
  const maxStart = ALL_CHUNKS.length - chunkCount
  const start = Math.floor(Math.random() * (maxStart + 1))
  
  return { start, count: chunkCount }
}

function getHeaders() {
  return {
    accept: 'application/json, text/plain, */*',
    'content-type': 'application/json',
  }
}

function initiateConversation() {
  const url = `${API_BASE}/api/participant/projects/${PROJECT_ID}/conversations/initiate`
  const body = JSON.stringify({
    name: `k6 Mass Test - VU${__VU} - Iter${__ITER}`,
    pin: '',
    tag_id_list: [],
    user_agent: 'k6/0.x (mass load test)',
    source: 'PORTAL_AUDIO',
  })

  const res = http.post(url, body, {
    headers: getHeaders(),
    tags: { name: 'initiate_conversation' },
  })

  let conversationId = null
  try {
    const json = res.json()
    conversationId = json?.id
  } catch (_) {
    // Silently fail, will be caught by caller
  }
  return { res, conversationId }
}

function getUploadUrl(conversationId, filename) {
  const url = `${API_BASE}/api/participant/conversations/${conversationId}/get-upload-url`
  const timestamp = Date.now()
  const body = JSON.stringify({
    filename: `chunk-${timestamp}.webm`,
    content_type: 'audio/webm',
    conversation_id: conversationId,
  })

  const res = http.post(url, body, {
    headers: getHeaders(),
    tags: { name: 'get_upload_url' },
  })

  let uploadData = null
  try {
    const json = res.json()
    uploadData = {
      chunkId: json?.chunk_id,
      uploadUrl: json?.upload_url,
      fields: json?.fields,
      fileUrl: json?.file_url,
    }
  } catch (_) {
    // Silently fail
  }
  return { res, uploadData }
}

function uploadToStorage(uploadUrl, fields, fileData, filename) {
  const fd = new FormData()
  
  fd.append('acl', fields.acl)
  fd.append('Content-Type', fields['Content-Type'])
  fd.append('key', fields.key)
  fd.append('AWSAccessKeyId', fields.AWSAccessKeyId)
  fd.append('policy', fields.policy)
  fd.append('signature', fields.signature)
  fd.append('file', http.file(fileData, filename, 'audio/webm'))

  const res = http.post(uploadUrl, fd.body(), {
    headers: { 'Content-Type': 'multipart/form-data; boundary=' + fd.boundary },
    tags: { name: 'upload_to_storage' },
  })

  return res
}

function confirmUpload(conversationId, chunkId, fileUrl, timestamp) {
  const url = `${API_BASE}/api/participant/conversations/${conversationId}/confirm-upload`
  const body = JSON.stringify({
    chunk_id: chunkId,
    file_url: fileUrl,
    timestamp: timestamp,
    source: 'PORTAL_AUDIO',
  })

  const res = http.post(url, body, {
    headers: getHeaders(),
    tags: { name: 'confirm_upload' },
  })

  return res
}

function finishConversation(conversationId) {
  const url = `${API_BASE}/api/participant/conversations/${conversationId}/finish`
  
  const res = http.post(url, null, {
    headers: {
      accept: 'application/json, text/plain, */*',
    },
    tags: { name: 'finish_conversation' },
  })

  return res
}

function runConversation() {
  // Get random chunk selection for this conversation
  const { start, count } = getRandomChunkRange()
  const selectedChunks = ALL_CHUNKS.slice(start, start + count)

  // Initiate conversation
  const initRes = initiateConversation()
  const conversationId = initRes.conversationId
  
  if (!conversationId) {
    console.error(`VU${__VU}: Failed to initiate conversation`)
    return false
  }

  // Upload chunks (simulating real-time recording with 30s intervals)
  for (let i = 0; i < selectedChunks.length; i++) {
    const { data, filename } = selectedChunks[i]
    const timestamp = new Date().toISOString()
    
    const uploadUrlRes = getUploadUrl(conversationId, filename)
    if (!uploadUrlRes.uploadData) {
      // Even on error, maintain the recording interval
      if (i < selectedChunks.length - 1) sleep(SLEEP_SEC)
      continue
    }

    const { chunkId, uploadUrl, fields, fileUrl } = uploadUrlRes.uploadData
    
    const storageRes = uploadToStorage(uploadUrl, fields, data, filename)
    if (storageRes.status !== 204) {
      if (i < selectedChunks.length - 1) sleep(SLEEP_SEC)
      continue
    }

    const confirmRes = confirmUpload(conversationId, chunkId, fileUrl, timestamp)
    if (confirmRes.status !== 200) {
      if (i < selectedChunks.length - 1) sleep(SLEEP_SEC)
      continue
    }

    // Simulate recording interval: wait 30 seconds before next chunk is generated
    // (In real scenario, participant is still recording/talking during this time)
    if (i < selectedChunks.length - 1) {
      sleep(SLEEP_SEC)
    }
  }

  // Finish conversation
  const finishRes = finishConversation(conversationId)
  if (finishRes.status !== 200) {
    console.error(`VU${__VU}: Failed to finish conversation: ${finishRes.status}`)
    return false
  }

  return true
}

export default function main() {
  if (!PROJECT_ID) {
    console.error('PROJECT_ID is required')
    return
  }

  if (ALL_CHUNKS.length < MIN_CHUNKS) {
    console.error(`Not enough audio chunks. Need at least ${MIN_CHUNKS}, found ${ALL_CHUNKS.length}`)
    return
  }

  // Continuously create conversations until test duration ends
  while (true) {
    const success = runConversation()
    
    if (success) {
      // Think time between conversations (simulates user behavior)
      sleep(THINK_TIME)
    } else {
      // If failed, wait a bit before retrying
      sleep(5)
    }
  }
}
