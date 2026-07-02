#!/usr/bin/env bash
# Deploy host-helper on kubeadm WITHOUT building or pushing any image — so the box
# gets GPU stats + audio devices + monitors + Renny control NOW, before a Harbor
# host-helper image exists. It runs host_helper.py (mounted from a ConfigMap) on a
# stock python image, installing pactl/xrandr + python deps + kubectl at startup.
# (For production, switch to the built Harbor image in k8s-deploy.yaml.)
#
# Run ON THE BOX:  bash deploy-nobuild.sh
set -euo pipefail
NS=uneeq
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[host-helper] loading host_helper.py into a ConfigMap…"
kubectl -n "$NS" create configmap host-helper-src \
  --from-file=host_helper.py="$DIR/host_helper.py" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[host-helper] applying SA/RBAC + Deployment (python:3.12-slim) + Service + Ingress…"
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata: { name: host-helper, namespace: uneeq }
---
# ClusterRole (not namespaced Role): GPU-process→pod attribution needs to read
# pods across ALL namespaces (Riva TTS/LLM live in nim-models, ASR in uneeq) to
# map a PID's cgroup pod-UID to its pod name. Read-only pods; deployments patch
# stays for the Renny restart action.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: host-helper }
rules:
  - { apiGroups: [""], resources: ["pods","pods/log"], verbs: ["get","list"] }
  # nodes: read the InternalIP to build the on-box relay's ws:// URL.
  - { apiGroups: [""], resources: ["nodes"], verbs: ["get","list"] }
  # services: read the rag-frontend NodePort; create/manage the mic-relay service.
  - { apiGroups: [""], resources: ["services"], verbs: ["get","list","create","update","patch","delete"] }
  # configmaps: create/update the mic-relay source ConfigMap (Install Remote Mic Proxy).
  - { apiGroups: [""], resources: ["configmaps"], verbs: ["get","list","create","update","patch","delete"] }
  - { apiGroups: ["apps"], resources: ["deployments"], verbs: ["get","list","create","patch","update","delete"] }
  # deployments/scale subresource: `kubectl scale` (Disable/Enable NVIDIA RAG)
  - { apiGroups: ["apps"], resources: ["deployments/scale"], verbs: ["get","patch","update"] }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: host-helper }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: host-helper }
subjects: [ { kind: ServiceAccount, name: host-helper, namespace: uneeq } ]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: host-helper, namespace: uneeq, labels: { app: host-helper } }
spec:
  replicas: 1
  selector: { matchLabels: { app: host-helper } }
  template:
    metadata: { labels: { app: host-helper } }
    spec:
      serviceAccountName: host-helper
      nodeName: dell-test-0udaxtn8
      hostPID: true   # so nvidia-smi --query-compute-apps resolves host process NAMES
      containers:
        - name: host-helper
          image: python:3.12-slim
          imagePullPolicy: IfNotPresent
          workingDir: /app
          command: ["/bin/sh","-c"]
          args:
            - |
              set -e
              apt-get update
              apt-get install -y --no-install-recommends pulseaudio-utils x11-xserver-utils curl ca-certificates python3-tk
              pip install --no-cache-dir fastapi uvicorn pydantic httpx
              curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl
              chmod +x /usr/local/bin/kubectl
              exec uvicorn host_helper:app --host 0.0.0.0 --port 8086
          env:
            - { name: DISPLAY, value: ":1" }
            - { name: XAUTHORITY, value: "/host-xauth/Xauthority" }
            - { name: PULSE_SERVER, value: "unix:/run/user/1000/pulse/native" }
          ports: [ { containerPort: 8086 } ]
          securityContext: { privileged: true }
          resources:
            limits: { nvidia.com/gpu: 1 }
          volumeMounts:
            - { name: src, mountPath: /app }
            - { name: xsock, mountPath: /tmp/.X11-unix }
            - { name: xauth, mountPath: /host-xauth, readOnly: true }
            - { name: pulse, mountPath: /run/user/1000/pulse }
            # NIM model pull on kubeadm: the node's containerd socket + nerdctl
            # binary, plus NGC creds (so `nerdctl -n k8s.io pull nvcr.io/...` works
            # exactly like `docker pull` does on the Docker box).
            - { name: containerd-sock, mountPath: /run/containerd/containerd.sock }
            - { name: nerdctl-bin, mountPath: /usr/local/bin/nerdctl, readOnly: true }
            - { name: ngc-docker, mountPath: /root/.docker, readOnly: true }
      volumes:
        - { name: src, configMap: { name: host-helper-src } }
        - { name: xsock, hostPath: { path: /tmp/.X11-unix, type: Directory } }
        - { name: xauth, hostPath: { path: /run/user/1000/gdm, type: Directory } }
        - { name: pulse, hostPath: { path: /run/user/1000/pulse, type: Directory } }
        - { name: containerd-sock, hostPath: { path: /run/containerd/containerd.sock, type: Socket } }
        - { name: nerdctl-bin, hostPath: { path: /usr/local/bin/nerdctl, type: File } }
        # ngc-registry-credentials (.dockerconfigjson) → /root/.docker/config.json for nvcr.io auth.
        - { name: ngc-docker, secret: { secretName: ngc-registry-credentials, items: [ { key: .dockerconfigjson, path: config.json } ], optional: true } }
---
apiVersion: v1
kind: Service
metadata: { name: host-helper, namespace: uneeq }
spec:
  selector: { app: host-helper }
  ports: [ { port: 8086, targetPort: 8086 } ]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: host-helper
  namespace: uneeq
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
spec:
  ingressClassName: nginx
  rules:
    # Must register /host-admin on the SAME hosts the kiosk uses (named servers),
    # not just the catch-all default server — else a request with Host: localhost
    # hits the kiosk's localhost server (which only has /) and returns the kiosk.
    - host: digitalhuman.miniprem
      http: &hhpaths
        paths:
          - path: /host-admin(/|$)(.*)
            pathType: ImplementationSpecific
            backend: { service: { name: host-helper, port: { number: 8086 } } }
    - host: localhost
      http: *hhpaths
    - http: *hhpaths   # catch-all (LAN IP)
YAML

echo "[host-helper] waiting for rollout (first start installs deps — ~1-2 min)…"
kubectl -n "$NS" rollout status deploy/host-helper --timeout=240s || true
echo "[host-helper] test:  curl -s -H 'Host: localhost' http://127.0.0.1/host-admin/gpu"
