{{/*
Expand the name of the chart.
*/}}
{{- define "renny.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "renny.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

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