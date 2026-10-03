{{/* Image for one app: <registry>/<imagePrefix><app>:<imageTag>. */}}
{{- define "dw.image" -}}
{{- $g := .root.Values.global -}}
{{- printf "%s/%s%s:%s" (required "global.registry is required" $g.registry) $g.imagePrefix .app (required "global.imageTag is required" $g.imageTag) -}}
{{- end -}}

{{- define "dw.labels" -}}
app.kubernetes.io/name: dembrane-web
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: dembrane
app.kubernetes.io/version: {{ .root.Values.global.imageTag | quote }}
{{- end -}}

{{- define "dw.selector" -}}
app.kubernetes.io/name: dembrane-web
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "dw.secretName" -}}
{{- required "secretName is required" .Values.secretName -}}
{{- end -}}

{{/* A secret key as an env var. */}}
{{- define "dw.secretEnv" -}}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ include "dw.secretName" .root }}
      key: {{ .key }}
      {{- if .optional }}
      optional: true
      {{- end }}
{{- end -}}

{{/* APP_ENV and APP_RELEASE, which every unit reads. */}}
{{- define "dw.baseEnv" -}}
- name: APP_ENV
  value: {{ .Values.appEnv | quote }}
- name: APP_RELEASE
  value: {{ .Values.global.imageTag | quote }}
{{- end -}}

{{/* A map of name: value as env vars, in name order. */}}
{{- define "dw.mapEnv" -}}
{{- range $k, $v := . }}
- name: {{ $k }}
  value: {{ $v | toString | quote }}
{{- end }}
{{- end -}}

{{/* Postgres TLS: trust the CA that signs the DO server certificate (postgres.js and DBOS's
node-postgres both verify it). */}}
{{- define "dw.caEnv" -}}
- name: NODE_EXTRA_CA_CERTS
  value: {{ printf "%s/database-ca.crt" .Values.secretFiles.mountPath | quote }}
{{- end -}}

{{/* What the API and the worker share: settings, the database, the bucket keys, Vertex,
media, and every optional secret. */}}
{{- define "dw.appEnv" -}}
{{ include "dw.baseEnv" . }}
{{ include "dw.caEnv" . }}
- name: GOOGLE_APPLICATION_CREDENTIALS
  value: {{ printf "%s/gcp-sa.json" .Values.secretFiles.mountPath | quote }}
- name: MEDIA_URL
  value: "http://dembrane-web-media:8080"
{{- include "dw.mapEnv" .Values.env }}
{{ include "dw.secretEnv" (dict "root" . "name" "DATABASE_URL" "key" "DATABASE_URL") }}
{{ include "dw.secretEnv" (dict "root" . "name" "FILES_S3_ACCESS_KEY_ID" "key" "S3_ACCESS_KEY") }}
{{ include "dw.secretEnv" (dict "root" . "name" "FILES_S3_SECRET_ACCESS_KEY" "key" "S3_SECRET_KEY") }}
{{ include "dw.secretEnv" (dict "root" . "name" "STORAGE_S3_KEY" "key" "S3_ACCESS_KEY") }}
{{ include "dw.secretEnv" (dict "root" . "name" "STORAGE_S3_SECRET" "key" "S3_SECRET_KEY") }}
{{- range .Values.optionalSecretKeys }}
{{ include "dw.secretEnv" (dict "root" $ "name" . "key" . "optional" true) }}
{{- end }}
{{- end -}}

{{/* The secret files volume: Vertex key and database CA. */}}
{{- define "dw.secretFilesVolume" -}}
- name: secret-files
  secret:
    secretName: {{ include "dw.secretName" .root }}
    defaultMode: 0440
    items:
      {{- if .gcp }}
      - key: {{ .root.Values.secretFiles.gcpServiceAccountKey }}
        path: gcp-sa.json
      {{- end }}
      - key: {{ .root.Values.secretFiles.databaseCaKey }}
        path: database-ca.crt
- name: tmp
  emptyDir: {}
{{- end -}}

{{- define "dw.secretFilesMount" -}}
- name: secret-files
  mountPath: {{ .Values.secretFiles.mountPath }}
  readOnly: true
- name: tmp
  mountPath: /tmp
{{- end -}}

{{/* Distroless nonroot images (uid 65532). */}}
{{- define "dw.podSecurity" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  runAsGroup: 65532
  fsGroup: 65532
  seccompProfile:
    type: RuntimeDefault
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- range . }}
  - name: {{ . }}
  {{- end }}
{{- end }}
{{- end -}}

{{- define "dw.containerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
{{- end -}}

{{- define "dw.strategy" -}}
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: {{ .Values.rollout.maxUnavailable }}
    maxSurge: {{ .Values.rollout.maxSurge }}
{{- end -}}

{{/* HPA for a Deployment: dict root, component, name, hpa. */}}
{{- define "dw.hpa" -}}
{{- if .hpa.enabled }}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .name }}
  labels:
    {{- include "dw.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .name }}
  minReplicas: {{ .hpa.minReplicas }}
  maxReplicas: {{ .hpa.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .hpa.cpuUtilization }}
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
    scaleUp:
      stabilizationWindowSeconds: 60
{{- end }}
{{- end -}}

{{/* PDB: dict root, component, name, minAvailable. */}}
{{- define "dw.pdb" -}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}
  labels:
    {{- include "dw.labels" . | nindent 4 }}
spec:
  minAvailable: {{ .minAvailable }}
  selector:
    matchLabels:
      {{- include "dw.selector" . | nindent 6 }}
  unhealthyPodEvictionPolicy: AlwaysAllow
{{- end -}}

{{/* ClusterIP Service on 8080: dict root, component, name. */}}
{{- define "dw.service" -}}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}
  labels:
    {{- include "dw.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 8080
      targetPort: http
      protocol: TCP
  selector:
    {{- include "dw.selector" . | nindent 4 }}
{{- end -}}
