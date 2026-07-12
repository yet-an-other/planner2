import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { describe, it } from 'node:test'

const chart = new URL('../charts/planner', import.meta.url).pathname

const environments = [
  {
    name: 'proxmox',
    hostname: 'planner.bdgn.me',
    values: new URL('../charts/planner/values-proxmox.yaml', import.meta.url).pathname,
  },
  {
    name: 'hetzner',
    hostname: 'planner.ivan-b.com',
    values: new URL('../charts/planner/values-hetzner.yaml', import.meta.url).pathname,
  },
]

function render(values) {
  return execFileSync('helm', ['template', 'planner', chart, '-f', values], {
    encoding: 'utf8',
  })
}

function documentFor(rendered, kind) {
  const document = rendered
    .split(/^---\s*$/m)
    .find((candidate) => candidate.includes(`kind: ${kind}`))
  assert.ok(document, `expected rendered ${kind}`)
  return document
}

function assertIncludes(document, fragments) {
  for (const fragment of fragments) {
    assert.match(document, fragment)
  }
}

describe('Planner workload chart', () => {
  for (const environment of environments) {
    it(`renders the complete ${environment.name} workload contract`, () => {
      const rendered = render(environment.values)
      const deployment = documentFor(rendered, 'Deployment')
      const service = documentFor(rendered, 'Service')
      const certificate = documentFor(rendered, 'Certificate')
      const ingressRoute = documentFor(rendered, 'IngressRoute')
      const pdb = documentFor(rendered, 'PodDisruptionBudget')

      assertIncludes(deployment, [
        /replicas: 3/,
        /planner2:sha-[0-9a-f]{7}/,
        /automountServiceAccountToken: false/,
        /terminationGracePeriodSeconds: 30/,
        /maxUnavailable: 0/,
        /maxSurge: 1/,
        /name: planner-runtime-env/,
        /planner\.yet-an-other\.io\/runtime-env-checksum: "0{64}"/,
        /name: APP_VERSION\s+value: "sha-[0-9a-f]{7}"/,
        /path: \/healthz/,
        /startupProbe:/,
        /readinessProbe:/,
        /livenessProbe:/,
        /cpu: 50m/,
        /memory: 64Mi/,
        /memory: 256Mi/,
        /runAsNonRoot: true/,
        /runAsUser: 10001/,
        /readOnlyRootFilesystem: true/,
        /allowPrivilegeEscalation: false/,
        /drop:\s+- ALL/,
        /type: RuntimeDefault/,
        /topologyKey: kubernetes\.io\/hostname/,
        /whenUnsatisfiable: ScheduleAnyway/,
      ])
      assert.doesNotMatch(deployment, /limits:\s+cpu:/)

      assertIncludes(service, [/type: ClusterIP/, /targetPort: http/])
      assertIncludes(certificate, [
        new RegExp(`- ${environment.hostname.replaceAll('.', '\\.')}`),
        /name: letsencrypt-dns/,
        /kind: ClusterIssuer/,
        /secretName: planner-tls/,
      ])
      assertIncludes(ingressRoute, [
        new RegExp(`Host\\(\`${environment.hostname.replaceAll('.', '\\.')}\`\\)`),
        /- websecure/,
        /secretName: planner-tls/,
        /name: planner-affinity/,
        /httpOnly: true/,
        /secure: true/,
        /sameSite: lax/,
      ])
      assertIncludes(pdb, [/minAvailable: 2/])

      assert.doesNotMatch(rendered, /kind: (Role|RoleBinding|ServiceAccount|HorizontalPodAutoscaler|NetworkPolicy)\b/)
      assert.equal((rendered.match(/path: \/healthz/g) ?? []).length, 3)
    })
  }

  it('rejects missing or unsafe deployment inputs', () => {
    for (const override of [
      'image.tag=latest',
      'runtime.secretName=',
      'runtime.checksum=not-a-digest',
      'certificate.issuerName=',
      'ingress.hostname=',
    ]) {
      assert.throws(
        () =>
          execFileSync(
            'helm',
            [
              'template',
              'planner',
              chart,
              '-f',
              environments[0].values,
              '--set',
              override,
            ],
            { encoding: 'utf8', stdio: 'pipe' },
          ),
        `expected Helm schema to reject ${override}`,
      )
    }
  })
})
