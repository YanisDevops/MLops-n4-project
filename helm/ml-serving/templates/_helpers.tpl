{{- define "ml-serving.name" -}}taxi-duration{{- end -}}
{{- define "ml-serving.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}{{ default "taxi-duration-predictor" .Values.serviceAccount.name }}{{ else }}{{ .Values.serviceAccount.name }}{{ end }}
{{- end }}
