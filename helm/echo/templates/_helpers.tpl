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
- name: DISABLE_CORS
  value: {{ .Values.common.env.DISABLE_CORS | quote }}
- name: DISABLE_REDACTION
  value: {{ .Values.common.env.DISABLE_REDACTION | quote }}
- name: DISABLE_SENTRY
  value: {{ .Values.common.env.DISABLE_SENTRY | quote }}
- name: SERVE_API_DOCS
  value: {{ .Values.common.env.SERVE_API_DOCS | quote }}
# Feature flags
- name: TRANSCRIPTION_PROVIDER
  value: {{ .Values.common.env.TRANSCRIPTION_PROVIDER | quote }}
- name: FEATURE_FLAGS__ENABLE_CHAT_AUTO_SELECT
  value: {{ .Values.common.env.FEATURE_FLAGS__ENABLE_CHAT_AUTO_SELECT | quote }}
- name: FEATURE_FLAGS__ENABLE_CHAT_SELECT_ALL
  value: {{ .Values.common.env.FEATURE_FLAGS__ENABLE_CHAT_SELECT_ALL | quote }}
- name: FEATURE_FLAGS__ENABLE_WEBHOOKS
  value: {{ .Values.common.env.FEATURE_FLAGS__ENABLE_WEBHOOKS | quote }}
# Storage config
- name: STORAGE_S3_REGION
  value: {{ .Values.common.env.STORAGE_S3_REGION | quote }}
- name: STORAGE_S3_ENDPOINT
  value: {{ .Values.common.env.STORAGE_S3_ENDPOINT | quote }}
- name: STORAGE_S3_BUCKET
  value: {{ .Values.common.env.STORAGE_S3_BUCKET | quote }}
# Directus session config
- name: DIRECTUS_SESSION_COOKIE_NAME
  value: {{ .Values.directus.env.SESSION_COOKIE_NAME | quote }}
# Build version
- name: BUILD_VERSION
  value: {{ .Values.global.imageTag | quote }}
# LLM routing / embeddings (non-sensitive)
{{- with (default "" .Values.common.env.LLM__MULTI_MODAL_PRO__MODEL) }}
- name: LLM__MULTI_MODAL_PRO__MODEL
  value: {{ . | quote }}
{{- end }}
{{- with (default "" .Values.common.env.LLM__MULTI_MODAL_PRO__VERTEX_LOCATION) }}
- name: LLM__MULTI_MODAL_PRO__VERTEX_LOCATION
  value: {{ . | quote }}
{{- end }}
{{- with (default "" .Values.common.env.LLM__MULTI_MODAL_FAST__MODEL) }}
- name: LLM__MULTI_MODAL_FAST__MODEL
  value: {{ . | quote }}
{{- end }}
{{- with (default "" .Values.common.env.LLM__MULTI_MODAL_FAST__VERTEX_LOCATION) }}
- name: LLM__MULTI_MODAL_FAST__VERTEX_LOCATION
  value: {{ . | quote }}
{{- end }}
{{- with (default "" .Values.common.env.LLM__TEXT_FAST__MODEL) }}
- name: LLM__TEXT_FAST__MODEL
  value: {{ . | quote }}
{{- end }}
{{- with (default "" .Values.common.env.LLM__TEXT_FAST__API_VERSION) }}
- name: LLM__TEXT_FAST__API_VERSION
  value: {{ . | quote }}
{{- end }}
{{- with (default "" .Values.common.env.EMBEDDING_MODEL) }}
- name: EMBEDDING_MODEL
  value: {{ . | quote }}
{{- end }}
{{- with (default "" .Values.common.env.EMBEDDING_BASE_URL) }}
- name: EMBEDDING_BASE_URL
  value: {{ . | quote }}
{{- end }}
{{- end }}

{{/*
All secret-based environment variables
*/}}
{{- define "echo.secretEnvVars" -}}
# Core secrets
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
- name: ASSEMBLYAI_API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: ASSEMBLYAI_API_KEY
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
- name: GCP_SA_JSON
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: GCP_SA_JSON
- name: LLM__MULTI_MODAL_PRO__GCP_SA_JSON
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: GCP_SA_JSON
- name: LLM__MULTI_MODAL_PRO_2__GCP_SA_JSON
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: GCP_SA_JSON
- name: LLM__MULTI_MODAL_PRO_3__GCP_SA_JSON
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: GCP_SA_JSON
- name: LLM__MULTI_MODAL_FAST__GCP_SA_JSON
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: GCP_SA_JSON
- name: LLM__MULTI_MODAL_FAST_2__GCP_SA_JSON
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: GCP_SA_JSON
- name: LLM__MULTI_MODAL_FAST_3__GCP_SA_JSON
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: GCP_SA_JSON
- name: LLM__TEXT_FAST__API_KEY
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LLM__TEXT_FAST__API_KEY
- name: LLM__TEXT_FAST__API_BASE
  valueFrom:
    secretKeyRef:
      name: echo-backend-secrets
      key: LLM__TEXT_FAST__API_BASE
{{- end }}
