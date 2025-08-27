{{/*
Renny image template
*/}}
{{- define "image.renderer" -}}
{{- .Values.image -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "renny.labels" -}}
app.kubernetes.io/name: renny
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "renny.selectorLabels" -}}
app.kubernetes.io/name: renny
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}