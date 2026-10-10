export type Side = 'prod' | 'dev'

export type EnvSnapshot = {
  at: number
  /** DB tunnels found by their env file; `port` from its PORT line, nothing else read. */
  db: { env: string; side: Side | null; port: string | null }[]
  /** kubectl's current context; null = could not ask. */
  kube: string | null
  /** Trino port-forward answering on its port; null = could not probe. */
  trino: boolean | null
  /** api-v2's :9001 forward and, from the forwarder's argv, which far end. */
  api: { listening: boolean | null; farEnd: Side | null }
  verdict: Side | 'none'
}

declare module 'claude-code' {
  interface PluginState {
    hive: { env: EnvSnapshot | null }
  }
}
