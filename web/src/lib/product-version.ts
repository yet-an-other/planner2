import { getRuntimeConfig } from './runtime-config'

export function getProductVersion(): string {
  return getRuntimeConfig().productVersion
}
