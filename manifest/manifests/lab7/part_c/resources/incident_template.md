# Incident report (Lab C)

Name:
Date:
Cluster/VM:

---

## 1) Detect

What triggered investigation?

- ZAP finding (copy title + your interpretation):
- Nuclei finding (if relevant):
- Falco alert line (copy):
- Audit log snippet (copy):

---

## 2) Triage

What objects are involved?

- Namespace:
- Pod(s):
- ServiceAccount (if relevant):
- Time window:

What do you think happened (hypothesis)?

---

## 3) Contain

What would you do immediately (choose at least 2, explain why)?

- scale down deployment
- revoke/rotate token or secret
- tighten RBAC
- block image digest / redeploy clean image
- isolate namespace (NetworkPolicy / remove ingress)

---

## 4) Prevent recurrence (tie to Labs A/B)

Choose at least one control you would add:

- RBAC least privilege change
- disable automountServiceAccountToken for services that do not need it
- add safer securityContext defaults
- add secrets scanning gate
- add SAST rule / fix
- add IaC scan rule and block risky manifests

---

## 5) Evidence appendix

Paste the minimal required evidence:

- 1 ZAP item with your interpretation
- 1 Falco alert line
- 1 audit log snippet
