import { sleep } from 'k6'
import http from 'k6/http'
import { FormData } from 'https://jslib.k6.io/formdata/0.0.2/index.js'

const PROJECT_ID = __ENV.PROJECT_ID || '8cda68d1-051b-43b3-b0ad-12fb7eaf58a2'
const API_BASE = 'https://api.echo-next.dembrane.com'
const CHUNKS_DIR = __ENV.CHUNKS_DIR || 'audioChunks'
const START = Number(__ENV.START || 0)
const END = Number(__ENV.END || 3)
const SLEEP_SEC = Number(__ENV.SLEEP || 30)

export const options = {
  scenarios: {
    default: {
      executor: 'shared-iterations',
      vus: Number(__ENV.VUS || 1),
      iterations: Number(__ENV.ITERATIONS || 1),
      maxDuration: __ENV.MAX_DURATION || '30m',
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
      console.error(`Failed to load chunk: ${path}`)
    }
  }
  return chunks
}

const CHUNKS = buildChunkList()

function getHeaders() {
  return {
    accept: 'application/json, text/plain, */*',
    'content-type': 'application/json',
  }
}

function initiateConversation() {
  const url = `${API_BASE}/api/participant/projects/${PROJECT_ID}/conversations/initiate`
  const body = JSON.stringify({
    name: 'k6 Load Test - Participant Recording',
    pin: '',
    tag_id_list: [],
    user_agent: 'k6/0.x (load test - dev environment)',
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
    console.error('Failed to parse initiate response')
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
    console.error('Failed to parse get-upload-url response')
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

export default function main() {
  if (!PROJECT_ID) {
    console.error('PROJECT_ID is required')
    return
  }

  if (!CHUNKS.length) {
    console.error('No audio chunks found')
    return
  }

  console.log(`Starting test with ${CHUNKS.length} chunks`)
  
  const initRes = initiateConversation()
  const conversationId = initRes.conversationId
  
  if (!conversationId) {
    console.error('Failed to initiate conversation')
    return
  }

  console.log(`Conversation ID: ${conversationId}`)

  for (let i = 0; i < CHUNKS.length; i++) {
    const { data, filename } = CHUNKS[i]
    const timestamp = new Date().toISOString()
    
    console.log(`Uploading chunk ${i + 1}/${CHUNKS.length}: ${filename}`)
    
    // Start the chunk upload (this happens in parallel with recording in real scenario)
    const uploadUrlRes = getUploadUrl(conversationId, filename)
    if (!uploadUrlRes.uploadData) {
      console.error(`Failed to get upload URL for chunk ${i}`)
      if (i < CHUNKS.length - 1) sleep(SLEEP_SEC)
      continue
    }

    const { chunkId, uploadUrl, fields, fileUrl } = uploadUrlRes.uploadData
    
    const storageRes = uploadToStorage(uploadUrl, fields, data, filename)
    if (storageRes.status !== 204) {
      console.error(`Failed to upload to storage: ${storageRes.status}`)
      if (i < CHUNKS.length - 1) sleep(SLEEP_SEC)
      continue
    }

    const confirmRes = confirmUpload(conversationId, chunkId, fileUrl, timestamp)
    if (confirmRes.status !== 200) {
      console.error(`Failed to confirm upload: ${confirmRes.status}`)
      if (i < CHUNKS.length - 1) sleep(SLEEP_SEC)
      continue
    }

    console.log(`Successfully uploaded chunk ${i + 1}/${CHUNKS.length}`)
    
    // Simulate recording interval: wait 30 seconds before next chunk is generated
    // (In real scenario, user is still recording during this time)
    if (i < CHUNKS.length - 1) {
      sleep(SLEEP_SEC)
    }
  }

  console.log('All chunks uploaded. Finishing conversation...')
  const finishRes = finishConversation(conversationId)
  if (finishRes.status === 200) {
    console.log('Conversation finished successfully')
  } else {
    console.error(`Failed to finish conversation: ${finishRes.status}`)
  }

  console.log(`Test completed. Conversation ID: ${conversationId}`)
}
