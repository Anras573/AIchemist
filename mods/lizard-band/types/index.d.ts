export type Finding = {
  file: string
  name: string
  ccn: number
  line: number
}

export type LizardSnapshot = {
  // Files lizard was asked about (changed files, capped).
  scanned: number
  threshold: number
  // Functions above the threshold, most complex first.
  findings: Finding[]
}

declare module 'claude-code' {
  interface PluginState {
    'aichemist-lizard-band': {
      snapshot: LizardSnapshot | null
      isHidden: boolean
    }
  }
}
