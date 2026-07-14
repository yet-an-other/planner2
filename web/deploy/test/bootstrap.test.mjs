import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { chmod, cp, mkdir, mkdtemp, readFile, symlink, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { afterEach, describe, it } from 'node:test'

const sourceDeploy = new URL('..', import.meta.url).pathname
const COOKIE_KEY = 'ab'.repeat(32)
const SECRET = 'private-client-secret=value'
const CLIENT_ID = 'planner.apps.googleusercontent.com'
const workspaces = []

function runtimeEnv() {
  return [
    `VITE_GOOGLE_CLIENT_ID=${CLIENT_ID}`,
    `GOOGLE_CLIENT_ID=${CLIENT_ID}`,
    `GOOGLE_CLIENT_SECRET=${SECRET}`,
    `SESSION_COOKIE_KEY=${COOKIE_KEY}`,
    '',
  ].join('\n')
}

async function createWorkspace({ ready = true } = {}) {
  const root = await mkdtemp(path.join(tmpdir(), 'planner-bootstrap-test-'))
  workspaces.push(root)
  const deploy = path.join(root, 'deploy')
  const bin = path.join(root, 'bin')
  const home = path.join(root, 'home')
  await Promise.all([
    mkdir(path.join(deploy, 'scripts'), { recursive: true }),
    mkdir(path.join(deploy, 'charts', 'planner-bootstrap'), { recursive: true }),
    mkdir(path.join(deploy, 'charts', 'planner'), { recursive: true }),
    mkdir(bin, { recursive: true }),
    mkdir(path.join(home, 'remote-kube', 'proxmox'), { recursive: true }),
    mkdir(path.join(home, 'remote-kube', 'hetzner'), { recursive: true }),
  ])
  await Promise.all([
    cp(path.join(sourceDeploy, 'bootstrap.sh'), path.join(deploy, 'bootstrap.sh')),
    cp(path.join(sourceDeploy, 'scripts', 'runtime-env.mjs'), path.join(deploy, 'scripts', 'runtime-env.mjs')),
    cp(path.join(sourceDeploy, 'scripts', 'release-state.mjs'), path.join(deploy, 'scripts', 'release-state.mjs')),
    writeFile(path.join(deploy, '.env.proxmox'), runtimeEnv()),
    writeFile(path.join(deploy, '.env.hetzner'), runtimeEnv()),
    writeFile(path.join(deploy, 'charts', 'planner-bootstrap', 'values-proxmox.yaml'), 'environmentValuesFile: values-proxmox.yaml\n'),
    writeFile(path.join(deploy, 'charts', 'planner-bootstrap', 'values-hetzner.yaml'), 'environmentValuesFile: values-hetzner.yaml\n'),
    writeFile(path.join(deploy, 'charts', 'planner', 'values-proxmox.yaml'), 'image:\n  tag: sha-abcdef0\n'),
    writeFile(path.join(deploy, 'charts', 'planner', 'values-hetzner.yaml'), 'image:\n  tag: sha-abcdef0\n'),
    writeFile(path.join(home, 'remote-kube', 'proxmox', 'config'), 'proxmox-kubeconfig'),
    writeFile(path.join(home, 'remote-kube', 'hetzner', 'config'), 'hetzner-kubeconfig'),
  ])

  const log = path.join(root, 'commands.log')
  await writeFile(log, '')
  await writeExecutable(path.join(bin, 'kubectl'), fakeKubectl)
  await writeExecutable(path.join(bin, 'helm'), fakeHelm)
  await symlink(process.execPath, path.join(bin, 'node'))

  return {
    root,
    deploy,
    log,
    env: {
      ...process.env,
      HOME: home,
      PATH: `${bin}:${process.env.PATH}`,
      FAKE_COMMAND_LOG: log,
      FAKE_READY: ready ? 'true' : 'false',
      PLANNER_BOOTSTRAP_TIMEOUT_SECONDS: ready ? '600' : '0',
      PLANNER_BOOTSTRAP_POLL_SECONDS: '0',
    },
  }
}

async function writeExecutable(file, contents) {
  await writeFile(file, contents)
  await chmod(file, 0o755)
}

function runBootstrap(workspace, args, { input, beforeStdinEnd = () => {} } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn('bash', [path.join(workspace.deploy, 'bootstrap.sh'), ...args], {
      cwd: workspace.root,
      env: workspace.env,
    })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', reject)
    child.on('close', (status) => resolve({ status, stdout, stderr }))
    beforeStdinEnd()
    if (input === undefined) child.stdin.end()
    else child.stdin.end(input)
  })
}

function assertSecretFree(text) {
  assert.doesNotMatch(text, new RegExp(SECRET.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  assert.doesNotMatch(text, new RegExp(COOKIE_KEY))
  assert.doesNotMatch(text, new RegExp(CLIENT_ID.replaceAll('.', '\\.')))
}

afterEach(async () => {
  const { rm } = await import('node:fs/promises')
  await Promise.all(workspaces.splice(0).map((workspace) => rm(workspace, { recursive: true, force: true })))
})

describe('bootstrap public command', () => {
  it('rejects unknown clusters and flags before invoking cluster tools', async () => {
    const workspace = await createWorkspace()

    const invalidCluster = await runBootstrap(workspace, ['production'], {
      // Exercise the Linux race where validation exits before the parent closes stdin.
      beforeStdinEnd: () => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 20),
    })
    const invalidFlag = await runBootstrap(workspace, ['proxmox', '--insecure-skip-tls-verify'])

    assert.notEqual(invalidCluster.status, 0)
    assert.notEqual(invalidFlag.status, 0)
    assert.match(invalidCluster.stderr, /proxmox\|hetzner/)
    assert.match(invalidFlag.stderr, /unknown option/i)
    assert.equal(await readFile(workspace.log, 'utf8'), '')
  })

  it('applies namespace then external Secret, bootstraps Argo, and waits for readiness', async () => {
    const workspace = await createWorkspace()

    const result = await runBootstrap(workspace, ['proxmox'])
    const log = await readFile(workspace.log, 'utf8')

    assert.equal(result.status, 0, result.stderr)
    const namespace = log.indexOf('create namespace planner')
    const secret = log.indexOf('create secret generic planner-runtime-env')
    const helm = log.indexOf('helm upgrade --install planner')
    assert.ok(namespace >= 0 && secret > namespace && helm > secret, log)
    assert.match(log, /--kubeconfig .*remote-kube\/proxmox\/config/)
    assert.match(log, /helm upgrade --install planner .*--kubeconfig .*remote-kube\/proxmox\/config/)
    assert.match(log, /--set-string runtimeChecksum=[0-9a-f]{64}/)
    assert.match(log, /get application planner/)
    assert.match(log, /get deployment planner/)
    assert.match(log, /get certificate planner/)
    assert.doesNotMatch(log, /insecure-skip-tls-verify/)
    assertSecretFree(`${result.stdout}${result.stderr}${log}`)
    assert.match(result.stdout, /Synced and Healthy/)
  })

  it('rejects the render-only image seed before mutating the cluster', async () => {
    const workspace = await createWorkspace()
    await writeFile(
      path.join(workspace.deploy, 'charts', 'planner', 'values-proxmox.yaml'),
      'image:\n  tag: sha-0000000\n',
    )

    const result = await runBootstrap(workspace, ['proxmox'])

    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /image has not been released/i)
    assert.equal(await readFile(workspace.log, 'utf8'), '')
    assertSecretFree(`${result.stdout}${result.stderr}`)
  })

  it('supports no-wait after idempotent apply commands', async () => {
    const workspace = await createWorkspace()

    const result = await runBootstrap(workspace, ['proxmox', '--no-wait'])
    const log = await readFile(workspace.log, 'utf8')

    assert.equal(result.status, 0, result.stderr)
    assert.match(log, /apply -f -/)
    assert.match(log, /helm upgrade --install planner/)
    assert.doesNotMatch(log, /get application planner/)
    assert.match(result.stdout, /Reconciliation continues in Argo CD/)
    assertSecretFree(`${result.stdout}${result.stderr}${log}`)
  })

  it('renders a dry run without applying or upgrading resources', async () => {
    const workspace = await createWorkspace()

    const result = await runBootstrap(workspace, ['proxmox', '--dry-run'])
    const log = await readFile(workspace.log, 'utf8')

    assert.equal(result.status, 0, result.stderr)
    assert.match(log, /create secret generic planner-runtime-env .*--dry-run=client -o name/)
    assert.match(log, /helm template planner/)
    assert.doesNotMatch(log, /apply -f -/)
    assert.doesNotMatch(log, /helm upgrade/)
    assertSecretFree(`${result.stdout}${result.stderr}${log}`)
  })

  it('requires typed Hetzner confirmation unless --yes is supplied', async () => {
    const workspace = await createWorkspace()

    const rejected = await runBootstrap(workspace, ['hetzner'], { input: 'no\n' })
    assert.notEqual(rejected.status, 0)
    assert.match(rejected.stderr, /confirmation did not match/i)
    assert.doesNotMatch(await readFile(workspace.log, 'utf8'), /apply|upgrade/)

    await writeFile(workspace.log, '')
    const accepted = await runBootstrap(workspace, ['hetzner', '--yes', '--no-wait'])
    const log = await readFile(workspace.log, 'utf8')
    assert.equal(accepted.status, 0, accepted.stderr)
    assert.match(log, /remote-kube\/hetzner\/config/)
    assert.match(log, /helm upgrade --install planner/)
    assertSecretFree(`${accepted.stdout}${accepted.stderr}${log}`)
  })

  it('times out with actionable statuses and no secret disclosure', async () => {
    const workspace = await createWorkspace({ ready: false })

    const result = await runBootstrap(workspace, ['proxmox'])
    const log = await readFile(workspace.log, 'utf8')

    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /timed out/i)
    assert.match(result.stderr, /Argo CD Application:/)
    assert.match(result.stderr, /Planner Deployment:/)
    assert.match(result.stderr, /Planner Certificate:/)
    assert.match(log, /get events/)
    assertSecretFree(`${result.stdout}${result.stderr}${log}`)
  })
})

const fakeKubectl = `#!/bin/sh
set -eu
printf 'kubectl %s\\n' "$*" >> "$FAKE_COMMAND_LOG"
args="$*"
case "$args" in
  *"create namespace planner"*) printf 'apiVersion: v1\\nkind: Namespace\\nmetadata:\\n  name: planner\\n' ;;
  *"create secret generic planner-runtime-env"*"-o name"*) printf 'secret/planner-runtime-env\\n' ;;
  *"create secret generic planner-runtime-env"*) printf 'apiVersion: v1\\nkind: Secret\\nmetadata:\\n  name: planner-runtime-env\\n' ;;
  *"apply -f -"*) cat >/dev/null; printf 'applied\\n' ;;
  *"get clusterissuer letsencrypt-dns"*) printf 'True' ;;
  *"get application planner"*"jsonpath"*) if [ "$FAKE_READY" = true ]; then printf 'Synced Healthy'; else printf 'OutOfSync Degraded'; fi ;;
  *"get deployment planner"*"jsonpath"*) if [ "$FAKE_READY" = true ]; then printf '3'; else printf '2'; fi ;;
  *"get certificate planner"*"jsonpath"*) if [ "$FAKE_READY" = true ]; then printf 'True'; else printf 'False'; fi ;;
  *"get application planner"*) printf 'planner OutOfSync Degraded\\n' ;;
  *"get deployment planner"*) printf 'planner 2/3 unavailable\\n' ;;
  *"get certificate planner"*) printf 'planner False\\n' ;;
  *"get events"*) printf 'Warning Unhealthy planner readiness probe failed\\n' ;;
  *) : ;;
esac
`

const fakeHelm = `#!/bin/sh
set -eu
printf 'helm %s\\n' "$*" >> "$FAKE_COMMAND_LOG"
case "$1" in
  template) printf '%s\\n' 'kind: Application' ;;
  upgrade) printf '%s\\n' 'release planner upgraded' ;;
esac
`
