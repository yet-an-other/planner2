# Planner workload chart

This chart deploys the single-origin Planner SPA and API. It deliberately does
not create its runtime Secret: bootstrap owns the existing
`planner-runtime-env` Secret and supplies only a canonical SHA-256 checksum to
the pod template. All three replicas share that Secret and can decrypt every
valid Google Account Connection cookie.

The environment value files contain a non-deployable render seed
`sha-0000000`. Image publication and protected promotion replace it with an
immutable seven-character commit tag before a live installation.

## Rollouts

Updates keep all old replicas available until replacements pass `/healthz`:
`maxUnavailable` is zero, one surge pod is allowed, and voluntary disruptions
must leave two pods available. Hostname spreading is preferred but does not
make an undersized cluster unschedulable.

Traefik's Secure, HttpOnly, SameSite=Lax affinity cookie keeps a browser's SPA
shell and fingerprinted assets on one replica while two image versions coexist.
It is not application session storage. Planner's encrypted session remains
stateless and usable by every replica. If new pods do not become ready,
Kubernetes retains healthy old pods and reports a degraded rollout; this chart
does not automatically roll Git back.
