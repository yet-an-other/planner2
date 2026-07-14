#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

const IMAGE_TAG = /^sha-[0-9a-f]{7}$/
const RENDER_ONLY_SEED = 'sha-0000000'
const DEFAULT_PROXMOX_VALUES = 'deploy/charts/planner/values-proxmox.yaml'
const DEFAULT_HETZNER_VALUES = 'deploy/charts/planner/values-hetzner.yaml'
const LEGACY_HETZNER_VALUES = 'deploy/charts/planner/values-hetzner.yaml'

export const CONTAINER_INPUT_PATHS = Object.freeze([
  '.dockerignore',
  'Dockerfile',
  'package.json',
  'pnpm-workspace.yaml',
  'pnpm-lock.yaml',
  'web-ui',
  'server',
  'contracts',
])

export function validateImageTag(tag) {
  if (!IMAGE_TAG.test(tag)) {
    throw new Error('Expected an immutable image tag in sha-abcdef0 format')
  }
  return tag
}

export async function readImageTag(file) {
  const text = await readFile(file, 'utf8')
  return imageTagLocation(text).tag
}

/** Replace only the image.tag scalar, retaining comments and all other values. */
export async function updateImageTag(file, imageTag) {
  validateImageTag(imageTag)
  const text = await readFile(file, 'utf8')
  const location = imageTagLocation(text)
  const replacement = `${location.indent}tag: ${location.quote}${imageTag}${location.quote}${location.suffix}${location.newline}`
  const next = `${text.slice(0, location.start)}${replacement}${text.slice(location.end)}`
  await writeFile(file, next, 'utf8')
}

export async function isNewestContainerCommit(candidateCommit, {
  cwd = process.cwd(),
  mainRef = 'main',
} = {}) {
  const candidate = git(cwd, ['rev-parse', `${candidateCommit}^{commit}`])
  const newest = git(cwd, [
    'rev-list',
    '-1',
    mainRef,
    '--',
    ...CONTAINER_INPUT_PATHS,
  ])
  if (newest === '') {
    throw new Error(`No container-affecting commit exists on ${mainRef}`)
  }
  return candidate === newest
}

export async function advanceStaging({
  candidateCommit,
  imageTag,
  cwd = process.cwd(),
  mainRef = 'main',
  proxmoxValues = path.join(cwd, DEFAULT_PROXMOX_VALUES),
}) {
  validateImageTag(imageTag)
  const candidate = git(cwd, ['rev-parse', `${candidateCommit}^{commit}`])
  if (imageTag !== `sha-${candidate.slice(0, 7)}`) {
    throw new Error('Image tag does not match candidate commit')
  }
  if (!(await isNewestContainerCommit(candidate, { cwd, mainRef }))) {
    return { updated: false, reason: 'superseded' }
  }
  await updateImageTag(proxmoxValues, imageTag)
  return { updated: true, imageTag }
}

/** Copy staging's immutable image exactly; callers cannot supply a destination tag. */
export async function currentEnvironmentImage(environment, {
  cwd = process.cwd(),
} = {}) {
  const values = environment === 'proxmox'
    ? DEFAULT_PROXMOX_VALUES
    : environment === 'hetzner'
      ? DEFAULT_HETZNER_VALUES
      : undefined
  if (values === undefined) {
    throw new Error('Environment must be proxmox or hetzner')
  }
  return readImageTag(path.join(cwd, values))
}

export async function promoteProduction({
  cwd = process.cwd(),
  proxmoxValues = path.join(cwd, DEFAULT_PROXMOX_VALUES),
  hetznerValues = path.join(cwd, DEFAULT_HETZNER_VALUES),
} = {}) {
  const imageTag = await readImageTag(proxmoxValues)
  await updateImageTag(hetznerValues, imageTag)
  return imageTag
}

/**
 * Reconstruct the production release stack from oldest to newest values.
 * A transition back to the preceding tag is a rollback and pops the stack,
 * which makes a second invocation continue backward rather than roll forward.
 */
export async function rollbackProduction({
  cwd = process.cwd(),
  hetznerValues = path.join(cwd, DEFAULT_HETZNER_VALUES),
} = {}) {
  const current = await readImageTag(hetznerValues)
  const relativeValues = gitPath(cwd, hetznerValues)
  const historicalValuePaths = [...new Set([relativeValues, LEGACY_HETZNER_VALUES])]
  const commits = git(cwd, [
    'log',
    '--format=%H',
    '--reverse',
    '--',
    ...historicalValuePaths.map((valuePath) => `:(top)${valuePath}`),
  ])
    .split('\n')
    .filter(Boolean)
  const history = []

  for (const commit of commits) {
    for (const valuePath of historicalValuePaths) {
      try {
        const text = git(cwd, ['show', `${commit}:${valuePath}`], false)
        const tag = imageTagLocation(text).tag
        if (tag !== RENDER_ONLY_SEED) history.push(tag)
        break
      } catch {
        // Try the path used before the web delivery stack was nested.
      }
    }
  }
  if (current !== RENDER_ONLY_SEED && history.at(-1) !== current) {
    history.push(current)
  }

  const stack = []
  for (const tag of history) {
    if (tag === stack.at(-1)) continue
    if (stack.length > 1 && tag === stack.at(-2)) stack.pop()
    else stack.push(tag)
  }

  if (stack.at(-1) !== current || stack.length < 2) {
    throw new Error('No previous production image exists in Git history')
  }
  const previous = stack.at(-2)
  await updateImageTag(hetznerValues, previous)
  return previous
}

function imageTagLocation(text) {
  const lines = text.match(/.*(?:\r?\n|$)/g)?.filter(Boolean) ?? []
  let offset = 0
  let inImage = false
  const matches = []

  for (const line of lines) {
    const content = line.replace(/\r?\n$/, '')
    const newline = line.slice(content.length)
    if (/^image:\s*(?:#.*)?$/.test(content)) {
      if (inImage) throw new Error('Expected exactly one image.tag value')
      inImage = true
      offset += line.length
      continue
    }
    if (inImage && /^[^\s#]/.test(content)) inImage = false
    if (inImage) {
      const match = /^(\s+)tag:\s*(?:"([^"]+)"|'([^']+)'|([^\s#]+))([ \t]*(?:#.*)?)$/.exec(content)
      if (match) {
        const quote = match[2] !== undefined ? '"' : match[3] !== undefined ? "'" : ''
        const tag = match[2] ?? match[3] ?? match[4]
        matches.push({
          tag: validateImageTag(tag),
          indent: match[1],
          quote,
          suffix: match[5],
          newline,
          start: offset,
          end: offset + line.length,
        })
      }
    }
    offset += line.length
  }

  if (matches.length !== 1) {
    throw new Error('Expected exactly one image.tag value')
  }
  return matches[0]
}

function git(cwd, args, trim = true) {
  const output = execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
  return trim ? output.trim() : output
}

function gitPath(cwd, file) {
  const repositoryPrefix = git(cwd, ['rev-parse', '--show-prefix'])
  const relativeFromCwd = path.relative(path.resolve(cwd), path.resolve(file)).split(path.sep).join('/')
  const relative = path.posix.normalize(`${repositoryPrefix}${relativeFromCwd}`)
  if (relative === '..' || relative.startsWith('../')) {
    throw new Error('Environment values must be inside the Git repository')
  }
  return relative
}

async function main() {
  const [command, ...args] = process.argv.slice(2)
  if (command === 'stage' && args.length === 2) {
    const result = await advanceStaging({ candidateCommit: args[0], imageTag: args[1] })
    process.stdout.write(result.updated ? `${result.imageTag}\n` : 'superseded\n')
    return
  }
  if (command === 'current' && args.length === 1) {
    process.stdout.write(`${await currentEnvironmentImage(args[0])}\n`)
    return
  }
  if (command === 'promote' && args.length === 0) {
    process.stdout.write(`${await promoteProduction()}\n`)
    return
  }
  if (command === 'rollback' && args.length === 0) {
    process.stdout.write(`${await rollbackProduction()}\n`)
    return
  }
  throw new Error('Usage: release-state.mjs <stage COMMIT IMAGE_TAG|current ENVIRONMENT|promote|rollback>')
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  main().catch((error) => {
    process.stderr.write(`release state: ${error instanceof Error ? error.message : String(error)}\n`)
    process.exitCode = 1
  })
}
