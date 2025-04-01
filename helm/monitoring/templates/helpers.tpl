{{- define "basic-auth" -}}
{{- $user := .username -}}
{{- $pass := .password -}}
{{- printf "%s:{PLAIN}%s" $user $pass -}}
{{- end -}} 