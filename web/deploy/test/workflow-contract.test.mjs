import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { describe, it } from 'node:test'

const root = new URL('../../..', import.meta.url)

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
  it('uses resolvable action generations that run on Node.js 24', async () => {
    const workflows = await Promise.all([
      workflow('web-ci.yml'),
      workflow('web-publish.yml'),
      workflow('web-promote-production.yml'),
      workflow('web-rollback-production.yml'),
    ])
    const text = workflows.join('\n')

    for (const reference of [
      'actions/checkout@v7',
      'actions/setup-node@v6',
      'azure/setup-helm@v5',
      'pnpm/action-setup@v6',
      'docker/setup-qemu-action@v4',
      'docker/setup-buildx-action@v4',
      'docker/login-action@v4',
      'docker/build-push-action@v7',
      'aquasecurity/trivy-action@v0.36.0',
      'oras-project/setup-oras@v2',
    ]) {
      assert.ok(text.includes(reference), `missing current action reference: ${reference}`)
    }
    assert.doesNotMatch(
      text,
      /(?:actions\/checkout|actions\/setup-node|azure\/setup-helm|pnpm\/action-setup)@v4\b/,
    )
    assert.doesNotMatch(text, /aquasecurity\/trivy-action@0\./)
  })

  it('runs application, deployment, shell, workflow, and PR container gates', async () => {
    const text = await workflow('web-ci.yml')

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
      'rhysd/actionlint:1.7.12',
      'docker build --tag planner:pr web',
      'bash web/deploy/test/container-smoke.sh planner:pr',
    ]) assert.ok(text.includes(command), `missing CI command: ${command}`)
    assert.match(text, /container-smoke:\s+if: github\.event_name == 'pull_request'/)
    assertPinnedActions(text)
  })
})

describe('immutable image and staging workflow policy', () => {
  it('publishes only container inputs as scanned, attested multi-platform SHA images', async () => {
    const text = await workflow('web-publish.yml')

    assert.match(text, /workflow_dispatch:/)
    const paths = text.slice(text.indexOf('    paths:'), text.indexOf('\n\npermissions:'))
    for (const input of ['web/.dockerignore', 'web/Dockerfile', 'web/package.json', 'web/pnpm-workspace.yaml', 'web/pnpm-lock.yaml', 'web/web-ui/**', 'web/server/**', 'web/contracts/**']) {
      assert.match(paths, new RegExp(`- ${input.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`))
    }
    assert.doesNotMatch(paths, /- web\/deploy\//)
    assert.match(text, /platforms: linux\/amd64,linux\/arm64/)
    assert.match(text, /skopeo copy --override-os linux --override-arch amd64[\s\S]*oci-archive:\/tmp\/planner-image\.tar[\s\S]*docker-archive:\/tmp\/planner-amd64\.tar/)
    assert.match(text, /skopeo copy --override-os linux --override-arch arm64[\s\S]*oci-archive:\/tmp\/planner-image\.tar[\s\S]*docker-archive:\/tmp\/planner-arm64\.tar/)
    assert.match(text, /source_sha=\$\(git rev-list -1 "\$GITHUB_SHA" -- \.dockerignore Dockerfile package\.json pnpm-workspace\.yaml pnpm-lock\.yaml web-ui server contracts\)/)
    assert.match(text, /source-sha=\$source_sha/)
    assert.match(text, /tag=sha-\$\{source_sha::7\}/)
    assert.doesNotMatch(text, /:build-\$\{\{ github\.sha \}\}/)
    assert.match(text, /outputs: type=oci,dest=\/tmp\/planner-image\.tar/)

    const build = text.indexOf('Build one multi-platform OCI archive with attestations')
    const report = text.indexOf('Report high and critical vulnerabilities in the release digest')
    const block = text.indexOf('Block fixable critical vulnerabilities in the release digest')
    const publish = text.indexOf('Publish the exact scanned OCI archive')
    assert.ok(build >= 0 && report > build && block > report && publish > block)
    assert.match(text.slice(report, block), /input: \/tmp\/planner-amd64\.tar[\s\S]*severity: HIGH,CRITICAL[\s\S]*ignore-unfixed: false[\s\S]*exit-code: 0/)
    assert.match(text.slice(block, publish), /input: \/tmp\/planner-amd64\.tar[\s\S]*severity: CRITICAL[\s\S]*ignore-unfixed: true[\s\S]*exit-code: 1/)
    assert.match(text, /input: \/tmp\/planner-arm64\.tar[\s\S]*severity: HIGH,CRITICAL/)
    assert.match(text, /input: \/tmp\/planner-arm64\.tar[\s\S]*severity: CRITICAL[\s\S]*ignore-unfixed: true/)
    assert.match(text, /provenance: mode=max/)
    assert.match(text, /sbom: true/)
    assert.match(text, /oras cp --from-oci-layout[\s\S]*planner-image\.tar@\$root_digest[\s\S]*"\$IMAGE:\$IMAGE_TAG"/)
    assert.match(text, /oras manifest fetch "\$IMAGE@\$digest"/)
    assert.match(text, /expected_platforms='linux\/amd64 linux\/arm64'/)
    assert.doesNotMatch(text, /skopeo copy --all[\s\S]*docker:\/\/\$IMAGE:\$IMAGE_TAG/)
    assert.match(text, /packages: write/)
    assert.match(text, /attestations: write/)
    assertPinnedActions(text)
  })

  it('serializes newest-only latest and Proxmox advancement without touching production', async () => {
    const text = await workflow('web-publish.yml')
    const stage = text.slice(text.indexOf('advance-staging:'))

    assert.match(stage, /group: planner-staging-advance\s+cancel-in-progress: false/)
    assert.match(stage, /contents: write/)
    assert.match(stage, /SOURCE_SHA: \$\{\{ needs\.publish-immutable\.outputs\.source-sha \}\}/)
    assert.match(stage, /release-state\.mjs stage "\$SOURCE_SHA" "\$IMAGE_TAG"/)
    assert.match(stage, /result" == superseded/)
    assert.match(stage, /deploy\/charts\/planner\/values-proxmox\.yaml/)
    assert.doesNotMatch(stage, /values-hetzner/)
    assert.match(stage, /\[skip ci\]/)
    assert.match(stage, /git fetch origin main/)
    assert.match(stage, /git push origin HEAD:main/)
    assert.match(stage, /git rev-list -1 origin\/main -- \.dockerignore Dockerfile package\.json pnpm-workspace\.yaml pnpm-lock\.yaml web-ui server contracts/)
    assert.match(stage, /"\$newest" != "\$SOURCE_SHA"/)
    assert.match(stage, /imagetools create[\s\S]*\$IMAGE:latest[\s\S]*\$IMAGE:\$IMAGE_TAG/)
  })
})

describe('protected production workflow policy', () => {
  for (const [name, command] of [
    ['web-promote-production.yml', 'promote'],
    ['web-rollback-production.yml', 'rollback'],
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
