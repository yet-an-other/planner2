import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { describe, it } from 'node:test'

const dockerfileUrl = new URL('../../Dockerfile', import.meta.url)

describe('Planner runtime image contract', () => {
  it('runs the copied application as a fixed unprivileged user', async () => {
    const dockerfile = await readFile(dockerfileUrl, 'utf8')
    const runtimeStage = dockerfile.slice(dockerfile.lastIndexOf('FROM node:24-alpine'))

    assert.match(runtimeStage, /addgroup[^\n]+10001[^\n]+planner/)
    assert.match(runtimeStage, /adduser[^\n]+10001[^\n]+planner/)
    assert.match(runtimeStage, /COPY --from=build --chown=10001:10001/)
    assert.match(runtimeStage, /USER 10001:10001/)
    assert.doesNotMatch(runtimeStage, /RUN (?!add(?:group|user))/)
  })

  it('documents all runtime-only configuration without build-time OAuth arguments', async () => {
    const dockerfile = await readFile(dockerfileUrl, 'utf8')

    for (const name of [
      'VITE_GOOGLE_CLIENT_ID',
      'GOOGLE_CLIENT_ID',
      'GOOGLE_CLIENT_SECRET',
      'SESSION_COOKIE_KEY',
      'APP_VERSION',
    ]) {
      assert.match(dockerfile, new RegExp(name))
    }
    assert.doesNotMatch(dockerfile, /\b(?:ARG|ENV) VITE_GOOGLE_CLIENT_ID=/)
  })
})
