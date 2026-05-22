# Lab 7c -  Staging DAST + runtime detection + incident drill

You will evaluate the running nanoservices system like an attacker (DAST), then detect suspicious behavior at runtime, then write an incident record using concrete evidence.

This lab is designed for a single-node student VM.

We do not deploy a full SIEM/EDR stack (often too heavy for K3s-on-VM labs).

Instead we use:

- Staging DAST: OWASP ZAP baseline + Nuclei (run as Docker containers)
- Runtime detection: Falco on K3s (DaemonSet)
- API-level detection: Kubernetes audit logging (built-in) + lightweight analysis



## Learning objectives

By the end of this lab you can:

1) Run a baseline DAST scan and explain what the findings mean (not just copy/paste).
2) Compare ZAP vs Nuclei outputs and classify findings (exposure vs app weakness vs false positive).
3) Generate a runtime alert and capture evidence from Falco logs.
4) Enable Kubernetes audit logging and locate suspicious API actions (pods/exec, secret reads, RBAC changes).
5) Produce a short incident report: detect, triage, contain, prevent recurrence.



## Prerequisites

- Your nanoservices gateway responds at `http://localhost/`
- You have `kubectl` access to the cluster
- Docker is running

Verify:

```bash
curl -sS -i http://localhost/api/ping | head
kubectl get nodes -o wide
docker ps | head
```

---

## 1. Staging DAST with OWASP ZAP baseline

### What ZAP baseline does

- Sends common requests and checks for low-hanging security issues (headers, basic exposures).
- Baseline scanning is not a full penetration test. It is a repeatable regression check.

### 1.1. Run ZAP baseline against the gateway

```bash
cd ~/lab7/part_c
bash tools/01_zap_baseline.sh http://localhost/
```

Open the report on the VM (or copy it out):

- `reports/zap-report.html`

Learning task:

- Pick 3 findings and for each write:
  - what it means
  - whether it matters in this system
  - what you would change to address it

---

## 2. Nuclei scan and comparison

### What Nuclei does

- Runs template-based checks for known exposure patterns.
- Good for quickly catching misconfigurations and known fingerprints.

Run it:

```bash
bash tools/02_nuclei_scan.sh http://localhost/
```

Compare ZAP and Nuclei:

- Which findings overlap?
- Which are unique?
- Which look like false positives?



## 3. Runtime detection with Falco

### What Falco detects

- Suspicious behaviors at the OS/syscall level (e.g., a shell spawned in a container).
- It helps you detect "something strange/ unexpected happened" even if the attacker uses valid credentials.

### 3.1. Deploy Falco to the cluster

```bash
kubectl apply -f manifests/10_falco_ds.yaml
kubectl get pods -n falco -o wide
```

Tail Falco logs in one terminal:

```bash
kubectl logs -n falco -l app=falco --tail=200 -f
```

### 3.2. Generate a benign suspicious event

In another terminal, exec a shell into a service pod (adjust labels if needed):

```bash
export NS=lab4
kubectl get pods -n $NS
POD=$(kubectl get pods -n $NS -l app=checkout-fn -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$POD" ]; then
  POD=$(kubectl get pods -n $NS -o jsonpath='{.items[0].metadata.name}')
fi
kubectl exec -n $NS -it "$POD" -- sh -c 'id; uname -a; echo hello; sleep 1'
```

Expected:

- Falco logs show an alert about shell/exec in a container (wording varies by Falco ruleset).

Evidence to capture:

- the Falco alert line(s)
- the pod name and namespace



## 4. Kubernetes audit logs as a VM-friendly alternative to Wazuh

### Why audit logs

- Many important security events are API actions:
  - exec into pod
  - read secret
  - create/update RBAC bindings

- Audit logs record who did what, when, and to which object.

### 4.1. Install an audit policy file

```bash
sudo mkdir -p /etc/rancher/k3s
sudo cp manifests/20_audit-policy.yaml /etc/rancher/k3s/audit-policy.yaml
```

### 4.2. Enable audit logging in K3s (systemd override)

This step restarts K3s.

```bash
sudo mkdir -p /etc/systemd/system/k3s.service.d
sudo cp manifests/21_k3s-audit-override.conf /etc/systemd/system/k3s.service.d/21-audit.conf
sudo systemctl daemon-reload
sudo systemctl restart k3s
sudo systemctl status k3s --no-pager -l | sed -n '1,120p'
```

Verify audit file exists:

```bash
sudo ls -la /var/lib/rancher/k3s/server/logs/ | grep kube-audit || true
```

### 4.3. Create high-signal audit events and find them

Trigger actions:

```bash
kubectl -n kube-system get secrets >/dev/null
kubectl -n $NS get pods >/dev/null
kubectl -n $NS get pods -o wide >/dev/null
```

Inspect recent audit records:

```bash
sudo tail -n 80 /var/lib/rancher/k3s/server/logs/kube-audit.log
```

Run a lightweight grep-based analysis script:

```bash
bash tools/03_audit_quickcheck.sh
```

Evidence to capture:

- one audit log snippet showing a relevant action (pods/exec, secrets, RBAC write)

---

## Part 5. Incident report (evidence-based)

Use the provided template and fill it in using your captured evidence:

```bash
cp -v resources/incident_template.md ./incident_report.md
```

Minimum required evidence:

- one ZAP finding (with your interpretation)
- one Falco alert line
- one audit log snippet

In your "Prevent recurrence" section, propose at least one control from Lab A or Lab B.

---

## Cleanup (optional)

```bash
kubectl delete -f manifests/10_falco_ds.yaml --ignore-not-found
```

To disable audit logging, remove the systemd override and restart k3s:

```bash
sudo rm -f /etc/systemd/system/k3s.service.d/21-audit.conf
sudo systemctl daemon-reload
sudo systemctl restart k3s
```
