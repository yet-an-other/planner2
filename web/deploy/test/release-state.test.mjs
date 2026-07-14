import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import { mkdtemp, mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { describe, it } from 'node:test'
import {
  advanceStaging,
  isNewestContainerCommit,
  promoteProduction,
  readImageTag,
  rollbackProduction,
  updateImageTag,
  validateImageTag,
} from '../scripts/release-state.mjs'

const PROXMOX = 'deploy/charts/planner/values-proxmox.yaml'
const HETZNER = 'deploy/charts/planner/values-hetzner.yaml'
const RELEASE_CLI = new URL('../scripts/release-state.mjs', import.meta.url).pathname

function git(cwd, ...args) {
  return execFileSync('git', args, { cwd, encoding: 'utf8' }).trim()
}

async function valuesFile(root, relativePath, tag, suffix = '') {
  const file = path.join(root, relativePath)
  await mkdir(path.dirname(file), { recursive: true })
  await writeFile(file, `# environment values\nimage:\n  repository: ghcr.io/example/planner\n  tag: ${tag}\nruntime:\n  checksum: unchanged\n${suffix}`)
  return file
}

async function repository() {
  const root = await mkdtemp(path.join(tmpdir(), 'planner-release-state-'))
  git(root, 'init', '-b', 'main')
  git(root, 'config', 'user.name', 'Planner Test')
  git(root, 'config', 'user.email', 'planner@example.test')
  await writeFile(path.join(root, 'Dockerfile'), 'FROM scratch\n')
  await writeFile(path.join(root, 'package.json'), '{}\n')
  await valuesFile(root, PROXMOX, 'sha-0000000')
  await valuesFile(root, HETZNER, 'sha-0000000')
  git(root, 'add', '.')
  git(root, 'commit', '-m', 'initial')
  return root
}

async function nestedWorkspaceRepository() {
  const root = await mkdtemp(path.join(tmpdir(), 'planner-nested-release-state-'))
  const workspace = path.join(root, 'web')
  git(root, 'init', '-b', 'main')
  git(root, 'config', 'user.name', 'Planner Test')
  git(root, 'config', 'user.email', 'planner@example.test')
  await mkdir(workspace, { recursive: true })
  await writeFile(path.join(workspace, 'Dockerfile'), 'FROM scratch\n')
  await writeFile(path.join(workspace, 'package.json'), '{}\n')
  await valuesFile(workspace, PROXMOX, 'sha-0000000')
  await valuesFile(workspace, HETZNER, 'sha-0000000')
  git(root, 'add', '.')
  git(root, 'commit', '-m', 'initial')
  return { root, workspace }
}

async function commitFile(root, relativePath, contents, message) {
  const file = path.join(root, relativePath)
  await mkdir(path.dirname(file), { recursive: true })
  await writeFile(file, contents)
  git(root, 'add', relativePath)
  git(root, 'commit', '-m', message)
  return git(root, 'rev-parse', 'HEAD')
}

async function commitProductionTag(root, tag, message = `production ${tag}`) {
  await updateImageTag(path.join(root, HETZNER), tag)
  git(root, 'add', HETZNER)
  git(root, 'commit', '-m', message)
  return git(root, 'rev-parse', 'HEAD')
}

describe('environment image values', () => {
  it('accepts only immutable seven-character hexadecimal SHA tags', () => {
    assert.equal(validateImageTag('sha-abcdef0'), 'sha-abcdef0')
    for (const tag of ['latest', 'sha-abcdef', 'sha-ABCDEFG', 'sha-abcdef00', 'abcdef0']) {
      assert.throws(() => validateImageTag(tag), /immutable image tag/i)
    }
  })

  it('reads and updates only image.tag while preserving unrelated content', async () => {
    const root = await repository()
    const file = path.join(root, PROXMOX)
    const before = await readFile(file, 'utf8')

    assert.equal(await readImageTag(file), 'sha-0000000')
    await updateImageTag(file, 'sha-abcdef0')

    const after = await readFile(file, 'utf8')
    assert.equal(await readImageTag(file), 'sha-abcdef0')
    assert.equal(after, before.replace('tag: sha-0000000', 'tag: sha-abcdef0'))
  })

  it('rejects missing, duplicate, and malformed image tags', async () => {
    const root = await repository()
    const file = path.join(root, PROXMOX)
    for (const contents of [
      'runtime:\n  checksum: unchanged\n',
      'image:\n  tag: sha-abcdef0\n  tag: sha-1234567\n',
      'image:\n  tag: latest\n',
    ]) {
      await writeFile(file, contents)
      await assert.rejects(() => readImageTag(file), /image\.tag|immutable image tag/i)
    }
  })
})

describe('staging advancement', () => {
  it('treats deployment-only commits as unrelated and rejects a superseded container commit', async () => {
    const root = await repository()
    const containerCommit = git(root, 'rev-parse', 'HEAD')
    await commitFile(root, 'deploy/README.md', 'operator notes\n', 'deployment docs')

    assert.equal(await isNewestContainerCommit(containerCommit, { cwd: root }), true)

    const newerContainerCommit = await commitFile(root, 'server/change.ts', 'export {}\n', 'server change')
    assert.equal(await isNewestContainerCommit(containerCommit, { cwd: root }), false)
    assert.equal(await isNewestContainerCommit(newerContainerCommit, { cwd: root }), true)

    const dockerignoreCommit = await commitFile(root, '.dockerignore', 'node_modules\n', 'docker context change')
    assert.equal(await isNewestContainerCommit(newerContainerCommit, { cwd: root }), false)
    assert.equal(await isNewestContainerCommit(dockerignoreCommit, { cwd: root }), true)
  })

  it('evaluates container inputs relative to a nested web workspace', async () => {
    const { root, workspace } = await nestedWorkspaceRepository()
    const containerCommit = git(root, 'rev-parse', 'HEAD')
    await commitFile(root, 'README.md', 'repository notes\n', 'repository docs')

    assert.equal(await isNewestContainerCommit(containerCommit, { cwd: workspace }), true)

    const newerContainerCommit = await commitFile(root, 'web/contracts/change.ts', 'export {}\n', 'contracts change')
    assert.equal(await isNewestContainerCommit(containerCommit, { cwd: workspace }), false)
    assert.equal(await isNewestContainerCommit(newerContainerCommit, { cwd: workspace }), true)
  })

  it('updates only Proxmox when candidate and tag identify the newest container commit', async () => {
    const root = await repository()
    const commit = git(root, 'rev-parse', 'HEAD')
    const tag = `sha-${commit.slice(0, 7)}`
    const productionBefore = await readFile(path.join(root, HETZNER), 'utf8')

    const result = await advanceStaging({ cwd: root, candidateCommit: commit, imageTag: tag })

    assert.deepEqual(result, { updated: true, imageTag: tag })
    assert.equal(await readImageTag(path.join(root, PROXMOX)), tag)
    assert.equal(await readFile(path.join(root, HETZNER), 'utf8'), productionBefore)
  })

  it('does not write staging for a superseded candidate or mismatched tag', async () => {
    const root = await repository()
    const oldCommit = git(root, 'rev-parse', 'HEAD')
    await commitFile(root, 'web-ui/change.ts', 'export {}\n', 'new web UI input')
    const before = await readFile(path.join(root, PROXMOX), 'utf8')

    assert.deepEqual(
      await advanceStaging({ cwd: root, candidateCommit: oldCommit, imageTag: `sha-${oldCommit.slice(0, 7)}` }),
      { updated: false, reason: 'superseded' },
    )
    assert.equal(await readFile(path.join(root, PROXMOX), 'utf8'), before)
    await assert.rejects(
      () => advanceStaging({ cwd: root, candidateCommit: 'HEAD', imageTag: 'sha-abcdef0' }),
      /does not match candidate commit/i,
    )
  })
})

describe('production transitions', () => {
  it('promotes the exact current Proxmox tag and changes only Hetzner', async () => {
    const root = await repository()
    await updateImageTag(path.join(root, PROXMOX), 'sha-abcdef0')
    const stagingBefore = await readFile(path.join(root, PROXMOX), 'utf8')

    const promoted = await promoteProduction({ cwd: root })

    assert.equal(promoted, 'sha-abcdef0')
    assert.equal(await readImageTag(path.join(root, HETZNER)), 'sha-abcdef0')
    assert.equal(await readFile(path.join(root, PROXMOX), 'utf8'), stagingBefore)
  })

  it('rejects promotion when staging contains a mutable or malformed value', async () => {
    const root = await repository()
    await writeFile(path.join(root, PROXMOX), 'image:\n  tag: latest\n')

    await assert.rejects(() => promoteProduction({ cwd: root }), /immutable image tag/i)
  })

  it('exposes promotion without an arbitrary destination-tag argument', async () => {
    const root = await repository()
    await updateImageTag(path.join(root, PROXMOX), 'sha-abcdef0')

    const promoted = spawnSync(process.execPath, [RELEASE_CLI, 'promote'], {
      cwd: root,
      encoding: 'utf8',
    })
    assert.equal(promoted.status, 0, promoted.stderr)
    assert.equal(promoted.stdout, 'sha-abcdef0\n')
    assert.equal(await readImageTag(path.join(root, HETZNER)), 'sha-abcdef0')

    await updateImageTag(path.join(root, HETZNER), 'sha-0000000')
    const rejected = spawnSync(process.execPath, [RELEASE_CLI, 'promote', 'sha-1234567'], {
      cwd: root,
      encoding: 'utf8',
    })
    assert.notEqual(rejected.status, 0)
    assert.equal(await readImageTag(path.join(root, HETZNER)), 'sha-0000000')
  })

  it('rolls back one release and repeated runs continue backward through production history', async () => {
    const root = await repository()
    await commitProductionTag(root, 'sha-aaaaaaa')
    await commitFile(root, 'README.md', 'unrelated\n', 'unrelated history')
    await commitProductionTag(root, 'sha-bbbbbbb')
    await commitProductionTag(root, 'sha-ccccccc')

    assert.equal(await rollbackProduction({ cwd: root }), 'sha-bbbbbbb')
    git(root, 'add', HETZNER)
    git(root, 'commit', '-m', 'rollback production')

    assert.equal(await rollbackProduction({ cwd: root }), 'sha-aaaaaaa')
    assert.equal(await readImageTag(path.join(root, HETZNER)), 'sha-aaaaaaa')
  })

  it('reads production history from the repository root when run in a nested web workspace', async () => {
    const { root, workspace } = await nestedWorkspaceRepository()
    const productionValues = path.join(workspace, HETZNER)
    for (const tag of ['sha-aaaaaaa', 'sha-bbbbbbb']) {
      await updateImageTag(productionValues, tag)
      git(root, 'add', `web/${HETZNER}`)
      git(root, 'commit', '-m', `production ${tag}`)
    }

    assert.equal(await rollbackProduction({ cwd: workspace }), 'sha-aaaaaaa')
    assert.equal(await readImageTag(productionValues), 'sha-aaaaaaa')
  })

  it('preserves production history from before the delivery stack moved under web', async () => {
    const root = await repository()
    await commitProductionTag(root, 'sha-aaaaaaa')
    await commitProductionTag(root, 'sha-bbbbbbb')
    const workspace = path.join(root, 'web')
    await mkdir(workspace)
    await rename(path.join(root, 'deploy'), path.join(workspace, 'deploy'))
    git(root, 'add', '-A')
    git(root, 'commit', '-m', 'move web delivery stack')

    assert.equal(await rollbackProduction({ cwd: workspace }), 'sha-aaaaaaa')
    assert.equal(await readImageTag(path.join(workspace, HETZNER)), 'sha-aaaaaaa')
  })

  it('skips malformed historical values but rejects malformed current state', async () => {
    const root = await repository()
    await commitProductionTag(root, 'sha-aaaaaaa')
    await writeFile(path.join(root, HETZNER), 'image:\n  tag: latest\n')
    git(root, 'add', HETZNER)
    git(root, 'commit', '-m', 'malformed historical state')
    await valuesFile(root, HETZNER, 'sha-bbbbbbb')
    git(root, 'add', HETZNER)
    git(root, 'commit', '-m', 'production sha-bbbbbbb')

    assert.equal(await rollbackProduction({ cwd: root }), 'sha-aaaaaaa')
    await writeFile(path.join(root, HETZNER), 'image:\n  tag: latest\n')
    await assert.rejects(() => rollbackProduction({ cwd: root }), /immutable image tag/i)
  })

  it('fails safely when there is no previous distinct production release', async () => {
    const root = await repository()

    await assert.rejects(() => rollbackProduction({ cwd: root }), /no previous production image/i)
  })
})
