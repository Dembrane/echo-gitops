{{- define "basic-auth" -}}
{{- $user := .username -}}
{{- $pass := .password -}}
{{- printf "%s:{PLAIN}%s" $user $pass -}}
{{- end -}} 

{{/*
Where the monitoring deployments run. With monitoring.nodePool set they stay on that node
pool, so the application's nodes keep their memory for the application. The daemon sets
(promtail, node-exporter) run on every node and do not use it.
*/}}
{{- define "monitoring.nodeSelector" -}}
{{- with (.Values.monitoring).nodePool }}
nodeSelector:
  doks.digitalocean.com/node-pool: {{ . | quote }}
{{- end }}
{{- end -}}
