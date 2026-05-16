{{- define "neo4j.fullname" -}}
{{- printf "%s-neo4j" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
