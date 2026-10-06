/** Guards clipboard work across connection shutdown and restart. */
export class PcConnectionState {
  private enabled: boolean = true;
  private generation: number = 0;

  block(): void {
    this.enabled = false;
    this.generation += 1;
  }

  enable(): void {
    this.enabled = true;
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  getGeneration(): number {
    return this.generation;
  }
}

export const pcConnectionState: PcConnectionState = new PcConnectionState();
