export type BeadsTask = {
  id: string
  title: string
  priority: number
  status: string
}

export type BeadsSnapshot = {
  inProgress: BeadsTask[]
  ready: BeadsTask[]
}

declare module 'claude-code' {
  interface PluginState {
    'aichemist-beads-band': {
      snapshot: BeadsSnapshot | null
      isHidden: boolean
    }
  }
}
