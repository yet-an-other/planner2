import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { describe, it } from 'node:test'

const root = new URL('../..', import.meta.url)

async function workflow(name) {
  return readFile(new URL(`.github/workflows/${name}`, root), 'utf8')
}

function assertPinnedActions(text) {
  const uses = [...text.matchAll(/uses:\s+([^\s]+)/g)].map((match) => match[1])
  assert.ok(uses.length > 0)
  for (const action of uses) {
    if (action.startsWith('./')) continue
    assert.match(action, /^[^@\s]+@(?:v?\d+(?:\.\d+){0,2}|[0-9a-f]{40})$/, `unpinned action: ${action}`)
  }
}

describe('CI workflow policy', () => {
  it('runs application, deployment, shell, workflow, and PR container gates', async () => {
    const text = await workflow('ci.yml')

    assert.match(text, /pull_request:/)
    assert.match(text, /workflow_call:/)
    assert.match(text, /permissions:\s+contents: read/)
    for (const command of [
      'pnpm install --frozen-lockfile',
      'pnpm test',
      'pnpm typecheck',
      'helm lint deploy/charts/planner',
      'helm template planner deploy/charts/planner',
      'helm lint deploy/charts/planner-bootstrap',
      'helm template planner deploy/charts/planner-bootstrap',
      'bash -n deploy/bootstrap.sh deploy/test/container-smoke.sh',
      'shellcheck deploy/bootstrap.sh deploy/test/container-smoke.sh',
      'rhysd/actionlint:1.7.7',
      'docker build --tag planner:pr .',
      'bash deploy/test/container-smoke.sh planner:pr',
    ]) assert.ok(text.includes(command), `missing CI command: ${command}`)
    assert.match(text, /container-smoke:\s+if: github\.event_name == 'pull_request'/)
    assertPinnedActions(text)
  })
})

describe('immutable image and staging workflow policy', () => {
  it('publishes only container inputs as scanned, attested multi-platform SHA images', async () => {
    const text = await workflow('publish.yml')

    const paths = text.slice(text.indexOf('    paths:'), text.indexOf('\n\npermissions:'))
    for (const input of ['Dockerfile', 'package.json', 'pnpm-workspace.yaml', 'pnpm-lock.yaml', 'web/**', 'server/**', 'shared/**']) {
      assert.match(paths, new RegExp(`- ${input.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`))
    }
    assert.doesNotMatch(paths, /- deploy\//)
    assert.match(text, /platform: \[linux\/amd64, linux\/arm64\]/)
    assert.match(text, /TRIVY_PLATFORM: \$\{\{ matrix\.platform \}\}/)
    assert.match(text, /platforms: linux\/amd64,linux\/arm64/)
    assert.match(text, /tag=sha-\$\{GITHUB_SHA::7\}/)
    assert.match(text, /tags: \$\{\{ env\.IMAGE \}\}:build-\$\{\{ github\.sha \}\}/)

    const build = text.indexOf('Build one multi-platform candidate with attestations')
    const report = text.indexOf('Report high and critical vulnerabilities in the release digest')
    const block = text.indexOf('Block fixable critical vulnerabilities in the release digest')
    const publish = text.indexOf('Tag the exact scanned digest as the immutable release')
    assert.ok(build >= 0 && report > build && block > report && publish > block)
    assert.match(text.slice(report, block), /image-ref: \$\{\{ env\.IMAGE \}\}@\$\{\{ env\.RELEASE_DIGEST \}\}[\s\S]*severity: HIGH,CRITICAL[\s\S]*ignore-unfixed: false[\s\S]*exit-code: 0/)
    assert.match(text.slice(block, publish), /image-ref: \$\{\{ env\.IMAGE \}\}@\$\{\{ env\.RELEASE_DIGEST \}\}[\s\S]*severity: CRITICAL[\s\S]*ignore-unfixed: true[\s\S]*exit-code: 1/)
    assert.match(text, /provenance: mode=max/)
    assert.match(text, /sbom: true/)
    assert.match(text, /imagetools create[\s\S]*\$IMAGE@\$RELEASE_DIGEST/)
    assert.match(text, /packages: write/)
    assert.match(text, /attestations: write/)
    assertPinnedActions(text)
  })

  it('serializes newest-only latest and Proxmox advancement without touching production', async () => {
    const text = await workflow('publish.yml')
    const stage = text.slice(text.indexOf('advance-staging:'))

    assert.match(stage, /group: planner-staging-advance\s+cancel-in-progress: false/)
    assert.match(stage, /contents: write/)
    assert.match(stage, /release-state\.mjs stage "\$GITHUB_SHA" "\$IMAGE_TAG"/)
    assert.match(stage, /result" == superseded/)
    assert.match(stage, /deploy\/charts\/planner\/values-proxmox\.yaml/)
    assert.doesNotMatch(stage, /values-hetzner/)
    assert.match(stage, /\[skip ci\]/)
    assert.match(stage, /git fetch origin main/)
    assert.match(stage, /git push origin HEAD:main/)
    assert.match(stage, /git rev-list -1 origin\/main -- Dockerfile package\.json pnpm-workspace\.yaml pnpm-lock\.yaml web server shared/)
    assert.match(stage, /imagetools create[\s\S]*\$IMAGE:latest[\s\S]*\$IMAGE:\$IMAGE_TAG/)
  })
})

describe('protected production workflow policy', () => {
  for (const [name, command] of [
    ['promote-production.yml', 'promote'],
    ['rollback-production.yml', 'rollback'],
  ]) {
    it(`${command}s only Hetzner desired image state behind the production environment`, async () => {
      const text = await workflow(name)

      assert.match(text, /workflow_dispatch:\s*\n/)
      assert.doesNotMatch(text, /workflow_dispatch:[\s\S]{0,100}inputs:/)
      assert.match(text, /environment: production/)
      assert.match(text, /group: planner-production-image-state\s+cancel-in-progress: false/)
      assert.match(text, /permissions:\s+contents: write/)
      assert.match(text, new RegExp(`release-state\\.mjs ${command}(?:\\)|\\n)`))
      assert.match(text, /deploy\/charts\/planner\/values-hetzner\.yaml/)
      assert.match(text, /\[skip ci\]/)
      assert.match(text, /git fetch origin main/)
      assert.match(text, /git push origin HEAD:main/)
      assert.doesNotMatch(text, /kubectl|curl|planner\.bdgn\.me|image[_-]tag.*workflow_dispatch/i)
      assert.doesNotMatch(text, /packages: write|id-token: write|attestations: write/)
      assertPinnedActions(text)
    })
  }
})
