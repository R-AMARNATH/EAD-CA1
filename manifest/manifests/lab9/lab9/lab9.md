# Lab 9: Build a secure gateway entry path with Ingress, TLS, and IAM

The goal of this lab is to understand how to design, build, test, and troubleshoot a secure platform entry path in Kubernetes.

The lab combines four themes:

- gateway and ingress architecture
- TLS at the edge
- IAM integration with Keycloak
- evaluation, testing, and troubleshooting

## Repository structure

- `lab9.md` — this main tutorial
- `gateway/` — readable local gateway source
- `manifests/` — Kubernetes manifests
- `scripts/` — helper scripts for testing
- `tls/` — placeholder folder for certificates you generate locally
- `examples/` — reference configuration examples

## Section map

- [9.1 Architecture overview](#91-architecture-overview)
- [9.2 Requirements and solution options](#92-requirements-and-solution-options)
- [9.3 Build the baseline gateway and ingress](#93-build-the-baseline-gateway-and-ingress)
- [9.4 Add TLS properly](#94-add-tls-properly)
- [9.5 Add IAM with Keycloak](#95-add-iam-with-keycloak)
- [9.6 Evaluation and testing](#96-evaluation-and-testing)
- [9.7 Troubleshooting](#97-troubleshooting)
- [9.8 Exercises](#98-exercises)
- [9.9 Reading and next steps](#99-reading-and-next-steps)



## 9.1 Architecture overview

### 9.1.1 What problem this lab solves

A microservice platform needs a **controlled entry path**. External clients should not call internal services directly. Instead, they should pass through an edge layer where the platform can apply common controls.

Those controls often include:

- routing
- TLS termination
- authentication
- token validation
- logging
- rate limiting
- request shaping
- observability hooks

### 9.1.2 Target architecture

~~~mermaid
flowchart TD
  Client[Browser or API client] --> HTTPS[HTTPS / TLS]
  HTTPS --> Ingress[Traefik Ingress]
  Ingress --> Gateway[Gateway Service]
  Gateway --> Checkout[checkout-svc]
  Checkout --> Pricing[pricing-svc]
  Checkout --> Inventory[inventory-svc]
  Client -. obtains token .-> Keycloak[Keycloak IdP]
  Gateway -. validates token .-> Keycloak
~~~

Interpretation:

- `Client -> Ingress -> Gateway` is **north-south traffic**
- `Gateway -> Checkout -> Pricing/Inventory` is **east-west traffic**
- Keycloak is not in every request’s data path, but it is part of the **identity trust path**

### 9.1.3 Trust boundaries

There are several important boundaries in this design:

1. **Client to edge boundary**  
   This is where TLS protects traffic and where the platform first receives external requests.

2. **Edge to internal service boundary**  
   This is where the platform translates external-facing routes into internal service calls.

3. **Identity trust boundary**  
   This is where the gateway decides whether to trust a bearer token based on issuer, signing keys, and token claims.



### 9.1.4 Learning objectives

1. explain why a gateway is used instead of exposing internal services directly
2. explain where TLS terminates and why
3. explain how bearer-token validation works at the edge
4. deploy and test a secure ingress path in Kubernetes
5. troubleshoot routing, TLS, and token-validation issues



## 9.2 Requirements and solution options

### 9.2.1 Functional requirements

The platform should:

- expose a simple external entry point
- hide internal service DNS names from clients
- support a secure checkout-style API path
- allow future extension for auth, rate limiting, and analytics

### 9.2.2 Security requirements

The platform should:

- support HTTPS
- validate bearer tokens for protected routes
- avoid trusting raw decoded tokens
- keep internal services off the public edge

### 9.2.3 Operational requirements

The platform should be:

- testable with `kubectl`, `curl`, and logs
- simple enough to run on a local K3s cluster
- structured so later labs can build on it

### 9.2.4 Solution options

There are several ways to expose services in Kubernetes.

#### Option A: Expose each service directly

This is easy to start with, but it is usually a poor platform design because:

- clients must know internal service names
- edge policy is duplicated or absent
- service sprawl leaks into the external interface

#### Option B: Use Ingress but route directly to many backends

This is more controlled than exposing every service, but it still spreads edge concerns across many routes and often lacks a coherent API boundary.

#### Option C: Use Ingress plus a gateway

This lab chooses this option to demonstrate:

- how ingress and gateway differ
- how a gateway hides internal topology
- where TLS and IAM fit naturally
- how platform policy can be centralised

### 9.2.5 Why this lab chooses self-signed TLS first

##### For teaching purposes, this lab starts with a **self-signed certificate** because:

- it works without needing a public CA
- Enables inspection of both key and certificate
- it makes the TLS lifecycle visible

##### Later, you should compare that with:

- internal CA-signed certificates
- public CA-signed certificates
- cert-manager automation
- service-mesh mTLS for east-west traffic

### 9.2.6 Why this lab chooses Keycloak as the IAM reference

##### Keycloak is used because it gives a concrete example of:

- an issuer
- a realm
- OIDC discovery
- JWKS key publication
- access token issuance

The goal is not to treat Keycloak as magic, but to show what any standards-based IdP provides.

## 9.3 Build the baseline gateway and ingress

### 9.3.1 Prerequisites

You need:

- K3s or another Kubernetes cluster
- Traefik enabled as ingress controller
- `kubectl`
- `curl`
- `openssl`
- Node.js 20+ if you want to study or run the local gateway source
- a running Keycloak instance later for section 9.5

Verify the cluster:

~~~bash
kubectl get nodes -o wide
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
kubectl get ingressclass
~~~

Expected:

- your node is `Ready`
- Traefik is running
- an ingress class exists

### 9.3.2 Create the namespace

~~~bash
cd ~/lab9
kubectl apply -f manifests/00-namespace.yaml
kubectl config set-context --current --namespace=lab9
kubectl get ns lab9
~~~

### 9.3.3 Deploy backend services

Apply the pricing, inventory, and checkout services:

~~~bash
kubectl apply -f manifests/10-pricing.yaml
kubectl apply -f manifests/11-inventory.yaml
kubectl apply -f manifests/12-checkout.yaml
kubectl get deploy,pods,svc
~~~

### 9.3.4 What these backend services do

This lab intentionally uses small services which focus on platform behaviour.

- `pricing` returns simple pricing information
- `inventory` returns simple stock information
- `checkout` receives a payload and returns a computed result

Read the checkout manifest and find the embedded Python server.

Questions to answer:

1. which route receives the checkout request?
2. where is the total calculated?
3. how is the response constructed?

This is important because later, when the gateway times out or retries, it is important to understand should know what the backend is actually doing.

### 9.3.5 Deploy the gateway

Apply:

~~~bash
kubectl apply -f manifests/20-gateway.yaml
kubectl get deploy,pods,svc -l app=gateway
~~~

The same gateway source is also provided in readable form at:

- `gateway/server.js`
- `gateway/package.json`

Use those files when you want to inspect and understand the code rather than reading it out of a manifest.

### 9.3.6 What the gateway currently does

##### The baseline gateway provides:

- `GET /`
- `GET /api/arch`
- `POST /api/checkout`

It also contains:

- optional bearer-token validation middleware
- timeout handling for backend POST requests

##### This is deliberate to demonstrate how security and resilience hooks fit into a gateway, even before those controls are fully activated.

### 9.3.7 Deploy the Ingress

Apply:

~~~bash
kubectl apply -f manifests/30-ingress.yaml
kubectl get ingress -o wide
kubectl describe ingress lab9-gateway
~~~

At this point you can test plain HTTP routing:

~~~bash
curl -i http://localhost/
curl -i http://localhost/api/arch
curl -i -H 'Content-Type: application/json' \
  -d '{"sku":1,"subtotal":100}' \
  http://localhost/api/checkout
~~~

Expected:

- `/` returns a small HTML message
- `/api/arch` returns JSON describing the architecture
- `/api/checkout` returns JSON from the backend checkout service

### 9.3.8 How the request path works

For `POST /api/checkout`, the path is:

1. the client sends a request to the ingress endpoint
2. Traefik matches the Ingress rule
3. Traefik forwards the request to `gateway-svc`
4. the gateway receives the request and proxies it to `checkout-svc`
5. the backend responds to the gateway
6. the gateway returns the result to the client

This is useful because:

- the client does not need to know `checkout-svc`
- edge policy can be enforced once
- the platform keeps control of the public API shape

### 9.3.9 Evidence capture

Capture evidence now before TLS and IAM change the path:

~~~bash
kubectl get pods -o wide
kubectl get svc -o wide
kubectl get endpoints gateway-svc checkout-svc pricing-svc inventory-svc -o wide
kubectl logs -l app=gateway --tail=100
~~~

---

## 9.4 Add TLS properly

### 9.4.1 Why TLS is being added here

So far, the gateway path works over plain HTTP. That is fine for understanding routing, but real entry paths should normally use HTTPS.

TLS provides:

- confidentiality of client-to-edge traffic
- server identity via certificate
- protection against passive interception

### 9.4.2 TLS terminology

#### Private key

The private key is the secret cryptographic key kept by the server side. It must be protected carefully.

- never publish it
- do not commit it to Git
- store it in a secure secret store or Kubernetes Secret
- access should be tightly controlled

#### Public certificate

The certificate contains the public key and metadata such as subject name, validity period, and issuer.

- this is what clients inspect
- it can be shared publicly
- it proves server identity when signed by a trusted CA, or when explicitly trusted in a lab

#### Self-signed certificate

A self-signed certificate is signed by its own private key.

- useful for labs and internal testing
- not automatically trusted by browsers or public clients
- good for teaching

#### CA-signed certificate

A certificate signed by a Certificate Authority is trusted if the client trusts that CA.

- appropriate for production or managed internal PKI
- supports a stronger trust model than a self-signed cert

### 9.4.3 Key sizes and security strength

For RSA, a typical modern teaching choice is:

- `2048-bit` RSA: still widely used and acceptable in many cases
- `3072-bit` or `4096-bit` RSA: stronger but slower

For real deployments, you may also see ECDSA certificates, which can offer strong security with smaller key sizes.

For this lab, use **RSA 2048** because it is widely supported and easy to explain - be aware that stronger or alternative choices exist.

### 9.4.4 Generate a self-signed certificate

Create a local folder for TLS material:

~~~bash
mkdir -p tls
~~~

Now generate a self-signed certificate and private key:

~~~bash
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout tls/lab9.key \
  -out tls/lab9.crt \
  -days 365 \
  -subj '/CN=localhost'
~~~

### 9.4.5 What those options mean

- `req` creates a certificate request flow
- `-x509` outputs a self-signed certificate instead of a CSR
- `-newkey rsa:2048` creates a new RSA private key of 2048 bits
- `-nodes` means “no DES encryption” on the private key, which is acceptable for a local lab but not ideal in every real-world context
- `-keyout` writes the private key
- `-out` writes the certificate
- `-days 365` sets validity duration
- `-subj` sets the certificate subject

### 9.4.6 Inspect what you created

List the files:

~~~bash
ls -l tls
~~~

Inspect the certificate:

~~~bash
openssl x509 -in tls/lab9.crt -text -noout | sed -n '1,120p'
~~~

Inspect the private key metadata:

~~~bash
openssl pkey -in tls/lab9.key -text -noout | sed -n '1,40p'
~~~

distinguish:

- which file is public
- which file is private
- where the subject appears
- how validity dates are represented

### 9.4.7 Put the certificate into Kubernetes

Create a TLS secret:

~~~bash
kubectl create secret tls lab9-tls \
  --cert=tls/lab9.crt \
  --key=tls/lab9.key
~~~

Check it exists:

~~~bash
kubectl get secret lab9-tls
kubectl describe secret lab9-tls
~~~

### 9.4.8 Why Kubernetes stores TLS this way

The Ingress resource references a Secret rather than embedding certificate material directly.

That separation is useful because:

- the Ingress rule stays focused on routing
- the key and certificate can be rotated independently of route logic
- different environments can use different secrets with the same route definition

### 9.4.9 Apply the TLS-enabled Ingress

Apply:

~~~bash
kubectl apply -f manifests/31-ingress-tls.yaml
kubectl describe ingress lab9-gateway | sed -n '1,200p'
~~~

### 9.4.10 Test HTTPS

With a self-signed certificate, use `-k` in curl to skip trust validation:

~~~bash
curl -k -i https://localhost/
curl -k -i https://localhost/api/arch
~~~

### 9.4.11 Test certificate details from the client side

Use OpenSSL to inspect the server certificate:

~~~bash
openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | sed -n '1,80p'
~~~

Inspect:

- certificate chain information
- subject
- whether the certificate is self-signed
- which protocol and cipher were negotiated

### 9.4.12 Logging and monitoring for TLS

In a production environment, edge TLS should also be observable.

Useful signals include:

- TLS handshake failures
- certificate expiry windows
- insecure protocol attempts
- unusual spikes in 4xx or 5xx responses after certificate change

Minimum:

- where Traefik logs are
- how to tell whether the issue is routing or TLS

Example:

~~~bash
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=100
~~~

### 9.4.13 Self-signed vs CA-signed recap

Self-signed:
- easy for labs
- not automatically trusted
- good for teaching certificate structure

CA-signed:
- appropriate for trusted environments
- scales better operationally
- fits production or managed internal PKI

### 9.4.14 Key architectural lesson

TLS is not just “run a command and move on.” You should understand:

- what was generated
- which part is secret
- how the Ingress uses the secret
- how to test the result
- how to reason about trust

---

## 9.5 Add IAM with Keycloak

### 9.5.1 Why IAM belongs in this lab

The entry path should not just be encrypted. It should also be able to decide **who is allowed to call it**.

This is where IAM fits:

- the client authenticates with the IdP
- the IdP issues an access token
- the gateway validates that token before allowing protected routes

### 9.5.2 What the gateway needs from an IdP

Any standards-based OIDC/OAuth identity provider should expose:

- an issuer
- token endpoints
- a JWKS endpoint for signing keys
- access tokens with claims

Keycloak is used here because it provides all of these clearly.

### 9.5.3 Minimum Keycloak setup

If you already completed the IAM lab, you may already have these:

- realm: `ead-security`
- client for testing
- user account
- access token issuance working

If not, the minimum steps are:

1. start Keycloak
2. create a realm called `ead-security`
3. create a public OIDC client for testing
4. obtain an access token for that client

### 9.5.4 Start Keycloak locally

If you do not already have a running Keycloak instance:

~~~bash
docker run --name keycloak \
  -p 8080:8080 \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=adminadmin \
  quay.io/keycloak/keycloak:26.0 start-dev
~~~

This uses development mode for learning. A production deployment would need stronger configuration.

### 9.5.5 Create the realm

In the admin console:

1. create a new realm named `ead-security`
2. keep defaults for now

The issuer base URL will be:

~~~text
http://localhost:8080/realms/ead-security
~~~

### 9.5.6 Discover the OIDC metadata

Run:

~~~bash
curl -s http://localhost:8080/realms/ead-security/.well-known/openid-configuration
~~~

Students should find:

- `issuer`
- `authorization_endpoint`
- `token_endpoint`
- `jwks_uri`

The **JWKS URI** matters because the gateway will use it to validate token signatures.

### 9.5.7 Create a test client

In Keycloak, create an OpenID Connect client for testing.

For a browser-style public client:

- client type: OpenID Connect
- public client
- standard flow enabled
- redirect URI set appropriately for your test tool

If you use Postman or a simple OAuth debugger, configure it to use Authorization Code with PKCE.

### 9.5.8 What kind of token the gateway should accept

The gateway should validate and consume an **access token**, not an ID token.

Explain why:

- an ID token is for the client
- an access token is for the resource server
- a gateway is acting as a resource server or edge resource validator

### 9.5.9 How gateway token validation works

The gateway does not trust a token simply because it can decode it.

It must validate:

- signature using the issuer’s JWKS
- issuer
- expiry
- optionally audience or authorised party depending on the token design

### 9.5.10 Study the gateway auth middleware

Open:

- `gateway/server.js`

Read the functions:

- `extractBearer`
- `maybeValidateToken`

Identify:

- how the bearer token is extracted from the header
- when auth is skipped for lab convenience
- when a missing token produces a 401
- when an invalid token produces a 401

### 9.5.11 Run the gateway locally with IAM settings

The gateway can be studied locally against the Keycloak realm:

~~~bash
cd ~/lab9/gateway
npm install
ISSUER=http://localhost:8080/realms/ead-security \
JWKS_URL=http://localhost:8080/realms/ead-security/protocol/openid-connect/certs \
REQUIRE_AUTH=true \
npm start
~~~

### 9.5.12 Test unauthenticated behaviour

Without a bearer token:

~~~bash
curl -i http://localhost:3000/api/arch
~~~

Expected:

- 401 Unauthorized

This proves the middleware is enforcing the policy.

### 9.5.13 Test authenticated behaviour

Once you obtain an access token from Keycloak, call:

~~~bash
ACCESS_TOKEN='PASTE_ACCESS_TOKEN_HERE'

curl -i http://localhost:3000/api/arch \
  -H "Authorization: Bearer $ACCESS_TOKEN"
~~~

Expected:

- 200 OK if the token is valid and the issuer/JWKS match

### 9.5.14 Why this is not magic

The gateway is doing real verification:

- the token must be signed by a key from the trusted issuer
- the issuer must match the configured realm
- the token must still be valid in time terms

This is why “decode-only” handling is unsafe.

### 9.5.15 Logging and monitoring for IAM at the edge

Useful signals include:

- count of 401 responses
- count of invalid signature errors
- unknown issuer errors
- token expiry failures
- spikes in unauthenticated access attempts

At minimum, inspect gateway logs:

~~~bash
kubectl logs -l app=gateway --tail=100
~~~

In a more mature platform, these should be forwarded into central logging and dashboards.

---

## 9.6 Evaluation and testing

### 9.6.1 Functional tests

Test the plain route:

~~~bash
curl -k -i https://localhost/
~~~

Test architecture route with token if auth is enabled:

~~~bash
curl -k -i https://localhost/api/arch \
  -H "Authorization: Bearer $ACCESS_TOKEN"
~~~

Test checkout route:

~~~bash
curl -k -i https://localhost/api/checkout \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"sku":1,"subtotal":100}'
~~~

### 9.6.2 Security tests

#### Test without token

~~~bash
curl -k -i https://localhost/api/arch
~~~

Expected:
- 401 if auth is required

#### Test with an obviously invalid token

~~~bash
curl -k -i https://localhost/api/arch \
  -H "Authorization: Bearer not-a-real-token"
~~~

Expected:
- 401 with invalid-token style failure

#### Test certificate details

~~~bash
openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | sed -n '1,80p'
~~~

### 9.6.3 Timeout test

The checkout service can simulate delay if sent this field:

- `"simulate_delay": true`

Call:

~~~bash
curl -k -i https://localhost/api/checkout \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"sku":1,"subtotal":100,"simulate_delay":true}'
~~~

If the gateway timeout is shorter than the backend delay, the gateway should fail fast with an error response.

This teaches that resilience starts even in a simple edge path.

### 9.6.4 Observability checks

Inspect:

~~~bash
kubectl get pods -o wide
kubectl logs -l app=gateway --tail=100
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=100
kubectl describe ingress lab9-gateway | sed -n '1,200p'
~~~

##### Checklist

- whether a failure is routing-related
- whether a failure is TLS-related
- whether a failure is IAM-related
- whether a failure is backend-timeout-related

---

## 9.7 Troubleshooting

### 9.7.1 If ingress does not route

Check:

~~~bash
kubectl get ingress -o wide
kubectl describe ingress lab9-gateway
kubectl get svc gateway-svc -o wide
kubectl get endpoints gateway-svc -o wide
kubectl get pods -l app=gateway -o wide
~~~

Common causes:

- wrong service name
- wrong target port
- ingress class mismatch
- gateway pod not healthy

### 9.7.2 If HTTPS does not work

Check:

~~~bash
kubectl get secret lab9-tls
kubectl describe ingress lab9-gateway
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=100
openssl x509 -in tls/lab9.crt -text -noout | sed -n '1,80p'
~~~

Common causes:

- TLS secret missing
- wrong secret name in Ingress
- certificate subject mismatch
- testing with a client that does not trust the self-signed certificate

### 9.7.3 If IAM fails

Check:

- `ISSUER` value
- `JWKS_URL` value
- whether Keycloak is reachable
- whether the token is an access token
- whether the token is expired

Useful checks:

~~~bash
curl -s http://localhost:8080/realms/ead-security/.well-known/openid-configuration
curl -i http://localhost:3000/api/arch -H "Authorization: Bearer $ACCESS_TOKEN"
~~~

### 9.7.4 If checkout times out

Check:

- gateway timeout configuration
- whether `simulate_delay` was used
- backend logs
- whether the failure is an intentional timeout rather than a network issue

---

## 9.8 Exercises

### Exercise 9.8.1 Architecture explanation

Explain, in your own words:

1. why the client should not call `checkout-svc` directly
2. how Ingress and gateway differ
3. where north-south traffic ends and east-west begins

### Exercise 9.8.2 TLS reasoning

Explain:

1. the difference between the private key and the public certificate
2. why the private key must be protected
3. why self-signed certificates are acceptable for a lab but not ideal for general production use

### Exercise 9.8.3 IAM reasoning

Explain:

1. what information the gateway needs from Keycloak
2. why the gateway should validate access tokens rather than ID tokens
3. why decode-only token handling is unsafe

### Exercise 9.8.4 Testing and evidence

Submit:

- one successful HTTPS response
- one failed unauthenticated response
- one successful authenticated response
- one output from `openssl s_client`
- one short paragraph describing what each proves

### Exercise 9.8.5 Timeout and resilience

Using the delayed checkout request, explain:

1. why a timeout is useful
2. why “wait forever” is a bad platform strategy
3. how this connects to later resilience topics like retries and circuit breakers

---

## 9.9 Reading and next steps

### Reading

- Kubernetes Ingress concepts: https://kubernetes.io/docs/concepts/services-networking/ingress/
- Traefik documentation: https://doc.traefik.io/traefik/
- OpenID Connect Core: https://openid.net/specs/openid-connect-core-1_0.html
- JWT: https://datatracker.ietf.org/doc/html/rfc7519
- JWT Best Current Practice: https://datatracker.ietf.org/doc/html/rfc8725
- Keycloak documentation: https://www.keycloak.org/documentation

### Next steps

Later labs can build on this by adding:

- richer edge API patterns
- rate limiting and overload controls
- east-west traffic controls
- service-mesh mTLS and telemetry
