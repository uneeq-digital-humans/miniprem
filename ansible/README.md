# UneeQ all-in-one — Ansible deploy (the non-ISO path)

Stand up the entire UneeQ digital-human stack (NIM Gemma LLM, Riva STT/TTS,
NVIDIA RAG, the RAG/conversation adapter, Phoenix, Renny renderer, the Dell
kiosk, host-helper) on a customer's own hardware — **without** burning the ISO.

Two modes, one vars file:

- **Bootstrap** (`bootstrap_cluster: true`): takes a bare **Ubuntu 24.04 + NVIDIA**
  box → single-node **kubeadm** cluster + GPU operator + ingress-nginx, then the
  full stack. Same end state as the ISO.
- **Existing cluster** (`bootstrap_cluster: false`): you bring a working cluster +
  GPU nodes + kubeconfig; the playbook only deploys the stack.

## Prerequisites

- Control machine with **Ansible 2.15+** and SSH to the target (or `localhost`).
- Target: Ubuntu 24.04, an NVIDIA GPU + driver (≥ 580 for Blackwell). Bootstrap
  mode needs sudo on the target.
- The `miniprem-2025` repo cloned on the target at `repo_dir` (default
  `/opt/uneeq/miniprem-2025`) — it carries the charts, manifests, and the
  `deploy-allinone.sh` the stack role drives.
- Credentials: an **NGC API key**, **Harbor** robot creds (Renny + kiosk images),
  and your **DHOP** platform key + tenant id + kiosk persona id.

## Quickstart

```bash
cd miniprem-2025/ansible
cp inventory.example.ini inventory.ini                 # set your target host
cp group_vars/all.example.yml group_vars/all.yml       # fill in creds + options
ansible-vault encrypt group_vars/all.yml               # recommended

ansible-playbook -i inventory.ini site.yml --ask-vault-pass
```

Useful selectors:

```bash
ansible-playbook -i inventory.ini site.yml --tags cluster   # just bring up the cluster
ansible-playbook -i inventory.ini site.yml --tags stack     # just (re)deploy the app stack
ansible-playbook -i inventory.ini site.yml --tags secrets   # just refresh secrets
```

## What each role does

| Role | Does |
|---|---|
| `preflight` | tool install (helm/kubectl), GPU check, asserts required creds present |
| `cluster` | kubeadm init + Calico + untaint + ingress-nginx + NVIDIA GPU operator *(bootstrap only)* |
| `secrets` | namespaces + NGC pull/api secrets, Harbor pull secret, Renny DHOP secret |
| `stack` | drives `deploy-allinone.sh` (full stack), then sets Renny `DHOP_TENANTID` + `RIVA_SERVER_ADDR` and the kiosk persona id |

The stack role intentionally **reuses `deploy-allinone.sh`** (the same orchestrator
the ISO runs) rather than re-implementing the NIM/Riva/RAG choreography in Ansible —
so there's one tested code path, not two.

## Notes / gotchas

- **Secrets:** never commit `group_vars/all.yml`; `ansible-vault encrypt` it. The
  DHOP api key is the raw base64 — **no `DHOP ` prefix** (that breaks auth).
- **Harbor:** the kiosk + `riva-ws-proxy` images live in the `dell-isg-containers`
  Harbor project — your robot needs **pull** access there, or STT/kiosk-image pulls
  401. (Renny lives in `uneeq`, which the project robot already has.)
- **Model:** `gemma_model` defaults to `google/gemma-2-9b-it` (pullable with a
  standard NGC key, fits with Riva + Renny + RAG). `gemma-3-27b-it` needs an extra
  NGC entitlement.
- **Persona** can also be set later in the kiosk Settings → Digital Human tab if the
  adapter isn't ready when the playbook runs.
- This is **structure-validated** (syntax + lint), not executed end-to-end here —
  dry-run against a scratch box before a customer hand-off.
