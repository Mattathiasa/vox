// Port of VoxCore/Safety/SafetyPolicy.swift: text matching any pattern needs a "yes".
export class SafetyPolicy {
  constructor(patterns) {
    this.patterns = patterns.map((p) => { try { return new RegExp(p, "i"); } catch { return null; } }).filter(Boolean);
  }
  needsConfirmation(text) { return this.patterns.some((re) => re.test(text)); }
}
