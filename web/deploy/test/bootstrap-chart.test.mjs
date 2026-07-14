import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { describe, it } from 'node:test'

const chart = new URL('../charts/planner-bootstrap', import.meta.url).pathname
const environments = [
  {
    name: 'proxmox',
    values: new URL('../charts/planner-bootstrap/values-proxmox.yaml', import.meta.url).pathname,
    workloadValues: 'values-proxmox.yaml',
  },
  {
    name: 'hetzner',
    values: new URL('../charts/planner-bootstrap/values-hetzner.yaml', import.meta.url).pathname,
    workloadValues: 'values-hetzner.yaml',
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

describe('Planner Argo CD bootstrap chart', () => {
  for (const environment of environments) {
    it(`renders a restricted, automatically reconciled ${environment.name} application`, () => {
      const rendered = render(environment.values)
      const project = documentFor(rendered, 'AppProject')
      const application = documentFor(rendered, 'Application')

      assert.match(project, /name: planner/)
      assert.match(project, /namespace: argocd/)
      assert.match(project, /sourceRepos:\s+- https:\/\/github\.com\/yet-an-other\/planner2\.git/)
      assert.match(project, /server: https:\/\/kubernetes\.default\.svc\s+namespace: planner/)
      assert.match(project, /clusterResourceWhitelist: \[\]/)

      const allowedKinds = [...project.matchAll(/kind: (Deployment|Service|PodDisruptionBudget|Certificate|IngressRoute)/g)]
        .map((match) => match[1])
        .sort()
      assert.deepEqual(allowedKinds, [
        'Certificate',
        'Deployment',
        'IngressRoute',
        'PodDisruptionBudget',
        'Service',
      ])
      assert.doesNotMatch(project, /kind: (Secret|Namespace|ConfigMap|Role|RoleBinding|ServiceAccount)/)

      assert.match(application, /name: planner/)
      assert.match(application, /namespace: argocd/)
      assert.match(application, /project: planner/)
      assert.match(application, /repoURL: https:\/\/github\.com\/yet-an-other\/planner2\.git/)
      assert.match(application, /targetRevision: main/)
      assert.match(application, /path: web\/deploy\/charts\/planner/)
      assert.match(application, new RegExp(`- ${environment.workloadValues.replace('.', '\\.')}`))
      assert.match(application, /releaseName: planner/)
      assert.match(application, /name: runtime\.checksum\s+value: "0{64}"\s+forceString: true/)
      assert.match(application, /server: https:\/\/kubernetes\.default\.svc\s+namespace: planner/)
      assert.match(application, /automated:\s+prune: true\s+selfHeal: true/)
      assert.match(application, /- CreateNamespace=true/)
      assert.match(application, /retry:\s+limit: 5/)
      assert.match(application, /backoff:\s+duration: 5s\s+factor: 2\s+maxDuration: 3m/)
      assert.doesNotMatch(application, /GOOGLE_CLIENT|CLIENT_SECRET|COOKIE_KEY/)
    })
  }

  it('rejects a missing or malformed checksum and unknown environment values file', () => {
    for (const override of [
      'runtimeChecksum=',
      'runtimeChecksum=not-a-checksum',
      'environmentValuesFile=values-other.yaml',
    ]) {
      assert.throws(
        () => execFileSync(
          'helm',
          ['template', 'planner', chart, '-f', environments[0].values, '--set', override],
          { encoding: 'utf8', stdio: 'pipe' },
        ),
        `expected Helm schema to reject ${override}`,
      )
    }
  })
})
