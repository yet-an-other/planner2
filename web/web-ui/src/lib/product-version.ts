import { getRuntimeConfig } from './runtime-config'

export function getProductVersion(): string {
  const productVersion = getRuntimeConfig().productVersion
  return /^\d/.test(productVersion) ? `v${productVersion}` : productVersion
}
