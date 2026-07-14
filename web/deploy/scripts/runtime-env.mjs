#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { realpathSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const RUNTIME_ENV_KEYS = Object.freeze([
  'GOOGLE_CLIENT_ID',
  'GOOGLE_CLIENT_SECRET',
  'SESSION_COOKIE_KEY',
  'VITE_GOOGLE_CLIENT_ID',
])

const knownKeys = new Set(RUNTIME_ENV_KEYS)

/** Parse the exact runtime Secret contract without evaluating or sourcing it. */
export function parseRuntimeEnv(text) {
  const entries = {}
  const lines = text.split(/\n/)

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index].endsWith('\r')
      ? lines[index].slice(0, -1)
      : lines[index]
    if (line.trim() === '' || line.trimStart().startsWith('#')) continue

    const separator = line.indexOf('=')
    if (separator <= 0) {
      throw new Error(`Malformed runtime environment entry on line ${index + 1}`)
    }

    const key = line.slice(0, separator)
    const value = line.slice(separator + 1)
    if (!/^[A-Z][A-Z0-9_]*$/.test(key)) {
      throw new Error(`Malformed runtime environment key on line ${index + 1}`)
    }
    if (!knownKeys.has(key)) {
      throw new Error(`Unknown runtime environment key: ${key}`)
    }
    if (Object.hasOwn(entries, key)) {
      throw new Error(`Duplicate runtime environment key: ${key}`)
    }
    if (value.length === 0) {
      throw new Error(`Runtime environment key must not be empty: ${key}`)
    }
    entries[key] = value
  }

  for (const key of RUNTIME_ENV_KEYS) {
    if (!Object.hasOwn(entries, key)) {
      throw new Error(`Missing runtime environment key: ${key}`)
    }
  }

  if (entries.VITE_GOOGLE_CLIENT_ID !== entries.GOOGLE_CLIENT_ID) {
    throw new Error('Google client ids must match')
  }
  if (!/^[0-9a-fA-F]{64}$/.test(entries.SESSION_COOKIE_KEY)) {
    throw new Error('SESSION_COOKIE_KEY must be 64 hexadecimal characters')
  }

  return entries
}

/** Hash a stable key-sorted representation so ordering/comments do not restart pods. */
export function runtimeEnvChecksum(entries) {
  const canonical = RUNTIME_ENV_KEYS
    .map((key) => `${key}=${entries[key]}\n`)
    .join('')
  return createHash('sha256').update(canonical, 'utf8').digest('hex')
}

async function main() {
  if (process.argv.length !== 3) {
    throw new Error('Usage: runtime-env.mjs <environment-file>')
  }
  const text = await readFile(process.argv[2], 'utf8')
  const checksum = runtimeEnvChecksum(parseRuntimeEnv(text))
  process.stdout.write(`${checksum}\n`)
}

const invokedPath = process.argv[1] && realpathSync(path.resolve(process.argv[1]))
if (invokedPath === realpathSync(fileURLToPath(import.meta.url))) {
  main().catch((error) => {
    const message = error instanceof Error ? error.message : 'Runtime environment validation failed'
    process.stderr.write(`Runtime environment validation failed: ${message}\n`)
    process.exitCode = 1
  })
}
