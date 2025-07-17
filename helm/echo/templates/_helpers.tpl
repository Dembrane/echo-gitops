{{/*
Common environment variables (including feature flags and non-sensitive config)
*/}}
{{- define "echo.commonEnvVars" -}}
# Core application config
- name: DEBUG_MODE
  value: {{ .Values.common.env.DEBUG_MODE | quote }}
- name: DIRECTUS_BASE_URL
  value: {{ .Values.common.env.DIRECTUS_BASE_URL | quote }}
- name: ADMIN_BASE_URL
  value: {{ .Values.common.env.ADMIN_BASE_URL | quote }}
- name: PARTICIPANT_BASE_URL
  value: {{ .Values.common.env.PARTICIPANT_BASE_URL | quote }}
- name: API_BASE_URL
  value: {{ .Values.common.env.API_BASE_URL | quote }}
- name: NEO4J_URI
  value: {{ .Values.common.env.NEO4J_URI | default "bolt://echo-neo4j:7687" | quote }}
- name: NEO4J_USERNAME
  value: {{ .Values.common.env.NEO4J_USERNAME | default "neo4j" | quote }}
- name: DISABLE_CORS
  value: {{ .Values.common.env.DISABLE_CORS | quote }}
- name: DISABLE_REDACTION
  value: {{ .Values.common.env.DISABLE_REDACTION | quote }}
- name: DISABLE_SENTRY
  value: {{ .Values.common.env.DISABLE_SENTRY | quote }}
- name: SERVE_API_DOCS
  value: {{ .Values.common.env.SERVE_API_DOCS | quote }}
# Feature flags
- name: ENABLE_CHAT_AUTO_SELECT
  value: {{ .Values.common.env.ENABLE_CHAT_AUTO_SELECT | quote }}
- name: ENABLE_AUDIO_LIGHTRAG_INPUT
  value: {{ .Values.common.env.ENABLE_AUDIO_LIGHTRAG_INPUT | quote }}
- name: ENABLE_RUNPOD_WHISPER_TRANSCRIPTION
  value: {{ .Values.common.env.ENABLE_RUNPOD_WHISPER_TRANSCRIPTION | quote }}
- name: ENABLE_ENGLISH_TRANSCRIPTION_WITH_LITELLM
  value: {{ .Values.common.env.ENABLE_ENGLISH_TRANSCRIPTION_WITH_LITELLM | quote }}
- name: ENABLE_LITELLM_WHISPER_TRANSCRIPTION
  value: {{ .Values.common.env.ENABLE_LITELLM_WHISPER_TRANSCRIPTION | quote }}
- name: ENABLE_RUNPOD_DIARIZATION
  value: {{ .Values.common.env.ENABLE_RUNPOD_DIARIZATION | quote }}
- name: DISABLE_MULTILINGUAL_DIARIZATION
  value: {{ .Values.common.env.DISABLE_MULTILINGUAL_DIARIZATION | quote }}
- name: RUNPOD_DIARIZATION_TIMEOUT
  value: {{ .Values.common.env.RUNPOD_DIARIZATION_TIMEOUT | quote }}
- name: RUNPOD_WHISPER_MAX_REQUEST_THRESHOLD
  value: {{ .Values.common.env.RUNPOD_WHISPER_MAX_REQUEST_THRESHOLD | quote }}
# Storage config
- name: STORAGE_S3_REGION
  value: {{ .Values.common.env.STORAGE_S3_REGION | quote }}
- name: STORAGE_S3_ENDPOINT
  value: {{ .Values.common.env.STORAGE_S3_ENDPOINT | quote }}
- name: STORAGE_S3_BUCKET
  value: {{ .Values.common.env.STORAGE_S3_BUCKET | quote }}
# LiteLLM API Version (non-sensitive)
- name: LIGHTRAG_LITELLM_API_VERSION
  value: {{ .Values.common.env.LIGHTRAG_LITELLM_API_VERSION | default "2023-05-15" | quote }}
# Directus session config
- name: DIRECTUS_SESSION_COOKIE_NAME
  value: {{ .Values.directus.env.SESSION_COOKIE_NAME | quote }}
# Build version
- name: BUILD_VERSION
  value: {{ .Values.global.imageTag | quote }}
{{- end }}

{{/*
All secret-based environment variables
*/}}
{{- define "echo.secretEnvVars" -}}
# Core secrets
- name: RUNPOD_DIARIZATION_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: RUNPOD_DIARIZATION_API_KEY
- name: RUNPOD_DIARIZATION_BASE_URL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: RUNPOD_DIARIZATION_BASE_URL
- name: DIRECTUS_TOKEN
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: DIRECTUS_ADMIN_TOKEN
- name: DIRECTUS_SECRET
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: DIRECTUS_SECRET
- name: OPENAI_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: OPENAI_API_KEY
- name: ANTHROPIC_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: ANTHROPIC_API_KEY
- name: REDIS_URL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: REDIS_URL
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: DATABASE_URL
- name: NEO4J_PASSWORD
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: NEO4J_PASSWORD
# Storage secrets
- name: STORAGE_S3_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: S3_ACCESS_KEY
- name: STORAGE_S3_SECRET
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: S3_SECRET_KEY
# LightRAG LiteLLM secrets
- name: LIGHTRAG_LITELLM_API_BASE
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_API_BASE
- name: LIGHTRAG_LITELLM_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_API_KEY
- name: LIGHTRAG_LITELLM_MODEL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_MODEL
# LightRAG Inference secrets
- name: LIGHTRAG_LITELLM_INFERENCE_MODEL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_INFERENCE_MODEL
- name: LIGHTRAG_LITELLM_INFERENCE_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_INFERENCE_API_KEY
- name: LIGHTRAG_LITELLM_INFERENCE_API_BASE
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_INFERENCE_API_BASE
- name: LIGHTRAG_LITELLM_INFERENCE_API_VERSION
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_INFERENCE_API_VERSION
# LightRAG Embedding secrets
- name: LIGHTRAG_LITELLM_EMBEDDING_API_VERSION
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_EMBEDDING_API_VERSION
- name: LIGHTRAG_LITELLM_EMBEDDING_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_EMBEDDING_API_KEY
- name: LIGHTRAG_LITELLM_EMBEDDING_API_BASE
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_EMBEDDING_API_BASE
- name: LIGHTRAG_LITELLM_EMBEDDING_MODEL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_EMBEDDING_MODEL
# LightRAG Text Structure Model secrets
- name: LIGHTRAG_LITELLM_TEXTSTRUCTUREMODEL_API_BASE
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_TEXTSTRUCTUREMODEL_API_BASE
- name: LIGHTRAG_LITELLM_TEXTSTRUCTUREMODEL_API_VERSION
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_TEXTSTRUCTUREMODEL_API_VERSION
- name: LIGHTRAG_LITELLM_TEXTSTRUCTUREMODEL_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_TEXTSTRUCTUREMODEL_API_KEY
- name: LIGHTRAG_LITELLM_TEXTSTRUCTUREMODEL_MODEL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_TEXTSTRUCTUREMODEL_MODEL
# LightRAG Audio Model secrets
- name: LIGHTRAG_LITELLM_AUDIOMODEL_API_BASE
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_AUDIOMODEL_API_BASE
- name: LIGHTRAG_LITELLM_AUDIOMODEL_API_VERSION
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_AUDIOMODEL_API_VERSION
- name: LIGHTRAG_LITELLM_AUDIOMODEL_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_AUDIOMODEL_API_KEY
- name: LIGHTRAG_LITELLM_AUDIOMODEL_MODEL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LIGHTRAG_LITELLM_AUDIOMODEL_MODEL
# LiteLLM Whisper secrets
- name: LITELLM_WHISPER_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LITELLM_WHISPER_API_KEY
- name: LITELLM_WHISPER_MODEL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LITELLM_WHISPER_MODEL
- name: LITELLM_WHISPER_URL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LITELLM_WHISPER_URL
# Large LiteLLM Model secrets
- name: LARGE_LITELLM_API_BASE
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LARGE_LITELLM_API_BASE
- name: LARGE_LITELLM_API_VERSION
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LARGE_LITELLM_API_VERSION
- name: LARGE_LITELLM_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LARGE_LITELLM_API_KEY
- name: LARGE_LITELLM_MODEL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LARGE_LITELLM_MODEL
# Medium LiteLLM Model secrets
- name: MEDIUM_LITELLM_API_BASE
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: MEDIUM_LITELLM_API_BASE
- name: MEDIUM_LITELLM_API_VERSION
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: MEDIUM_LITELLM_API_VERSION
- name: MEDIUM_LITELLM_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: MEDIUM_LITELLM_API_KEY
- name: MEDIUM_LITELLM_MODEL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: MEDIUM_LITELLM_MODEL
# Small LiteLLM Model secrets
- name: SMALL_LITELLM_API_BASE
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: SMALL_LITELLM_API_BASE
- name: SMALL_LITELLM_API_VERSION
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: SMALL_LITELLM_API_VERSION
- name: SMALL_LITELLM_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: SMALL_LITELLM_API_KEY
- name: SMALL_LITELLM_MODEL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: SMALL_LITELLM_MODEL
# RunPod secrets
- name: RUNPOD_WHISPER_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: RUNPOD_WHISPER_API_KEY
- name: RUNPOD_WHISPER_BASE_URL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: RUNPOD_WHISPER_BASE_URL
- name: RUNPOD_WHISPER_PRIORITY_BASE_URL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: RUNPOD_WHISPER_PRIORITY_BASE_URL
- name: RUNPOD_TOPIC_MODELER_URL
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: RUNPOD_TOPIC_MODELER_URL
- name: RUNPOD_TOPIC_MODELER_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: RUNPOD_TOPIC_MODELER_API_KEY
{{- end }}