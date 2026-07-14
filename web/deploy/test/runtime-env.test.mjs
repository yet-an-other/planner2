import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import { mkdtemp, chmod, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { describe, it } from 'node:test'
import {
  parseRuntimeEnv,
  runtimeEnvChecksum,
} from '../scripts/runtime-env.mjs'

const COOKIE_KEY = 'ab'.repeat(32)
const validEntries = [
  'VITE_GOOGLE_CLIENT_ID=planner.apps.googleusercontent.com',
  'GOOGLE_CLIENT_ID=planner.apps.googleusercontent.com',
  'GOOGLE_CLIENT_SECRET=secret=value==',
  `SESSION_COOKIE_KEY=${COOKIE_KEY}`,
]

function validText(lines = validEntries) {
  return `${lines.join('\n')}\n`
}

async function temporaryEnv(contents = validText()) {
  const directory = await mkdtemp(path.join(tmpdir(), 'planner-runtime-env-'))
  const file = path.join(directory, '.env.test')
  await writeFile(file, contents, { mode: 0o644 })
  return file
}

describe('runtime env parser', () => {
  it('accepts comments, blank lines, and values containing equals signs', () => {
    const parsed = parseRuntimeEnv(
      `# Planner runtime\n\n${validEntries[0]}\n${validEntries[1]}\nGOOGLE_CLIENT_SECRET=secret=value==\n${validEntries[3]}\n`,
    )

    assert.deepEqual(parsed, {
      VITE_GOOGLE_CLIENT_ID: 'planner.apps.googleusercontent.com',
      GOOGLE_CLIENT_ID: 'planner.apps.googleusercontent.com',
      GOOGLE_CLIENT_SECRET: 'secret=value==',
      SESSION_COOKIE_KEY: COOKIE_KEY,
    })
  })

  it('rejects malformed, unknown, duplicate, missing, and empty entries without echoing values', () => {
    const cases = [
      ['malformed', validText([...validEntries, 'NOT-AN-ENTRY'])],
      ['unknown', validText([...validEntries, 'SURPRISE=private-surprise'])],
      ['duplicate', validText([...validEntries, 'GOOGLE_CLIENT_SECRET=private-duplicate'])],
      ['missing', validText(validEntries.slice(0, -1))],
      ['empty', validText(validEntries.map((line) => line.startsWith('GOOGLE_CLIENT_SECRET=') ? 'GOOGLE_CLIENT_SECRET=' : line))],
    ]

    for (const [label, text] of cases) {
      assert.throws(
        () => parseRuntimeEnv(text),
        (error) => {
          assert.ok(error instanceof Error, label)
          assert.doesNotMatch(error.message, /private-|secret=value/)
          return true
        },
      )
    }
  })

  it('requires matching client ids and an exact 64-character hexadecimal cookie key', () => {
    assert.throws(
      () => parseRuntimeEnv(validText(validEntries.map((line) => line.startsWith('VITE_') ? 'VITE_GOOGLE_CLIENT_ID=other.apps.googleusercontent.com' : line))),
      /client ids must match/i,
    )
    assert.throws(
      () => parseRuntimeEnv(validText(validEntries.map((line) => line.startsWith('SESSION_') ? `SESSION_COOKIE_KEY=${'z'.repeat(64)}` : line))),
      /64 hexadecimal/i,
    )
  })

  it('computes an order-independent canonical checksum and permits identical keys across environments', () => {
    const first = parseRuntimeEnv(validText())
    const second = parseRuntimeEnv(validText([...validEntries].reverse()))

    assert.equal(runtimeEnvChecksum(first), runtimeEnvChecksum(second))
    assert.match(runtimeEnvChecksum(first), /^[0-9a-f]{64}$/)
    assert.equal(first.SESSION_COOKIE_KEY, second.SESSION_COOKIE_KEY)
  })
})

describe('runtime env CLI', () => {
  it('prints only the canonical checksum for a valid file and does not enforce file mode', async () => {
    const file = await temporaryEnv()
    await chmod(file, 0o644)

    const stdout = execFileSync(process.execPath, ['deploy/scripts/runtime-env.mjs', file], {
      cwd: new URL('../..', import.meta.url),
      encoding: 'utf8',
    })

    assert.match(stdout, /^[0-9a-f]{64}\n$/)
    assert.doesNotMatch(stdout, /planner|secret|apps\.googleusercontent|abab/)
  })

  it('fails without disclosing secret values', async () => {
    const file = await temporaryEnv(`${validText()}SURPRISE=private-surprise\n`)
    const result = spawnSync(process.execPath, ['deploy/scripts/runtime-env.mjs', file], {
      cwd: new URL('../..', import.meta.url),
      encoding: 'utf8',
    })

    assert.notEqual(result.status, 0)
    assert.doesNotMatch(`${result.stdout}${result.stderr}`, /private-surprise|secret=value/)
  })
})
