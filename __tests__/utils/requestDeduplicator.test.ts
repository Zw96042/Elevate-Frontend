import { RequestDeduplicator } from '../../lib/utils/request-deduplicator';

jest.mock('../../lib/utils/logger', () => ({
  logger: { debug: jest.fn(), info: jest.fn() },
  Modules: { DEDUP: 'Dedup' },
}));

describe('RequestDeduplicator invalidation', () => {
  beforeEach(() => RequestDeduplicator.clear());

  it('does not let an invalidated request delete its replacement', async () => {
    let finishOld: ((value: string) => void) | undefined;
    let finishNew: ((value: string) => void) | undefined;
    const oldRequest = RequestDeduplicator.deduplicate(
      'auth',
      () => new Promise(resolve => { finishOld = resolve; })
    );

    RequestDeduplicator.clearKey('auth');
    const newRequest = RequestDeduplicator.deduplicate(
      'auth',
      () => new Promise(resolve => { finishNew = resolve; })
    );
    finishOld?.('old');
    await oldRequest;

    const unexpected = jest.fn(async () => 'unexpected');
    const joined = RequestDeduplicator.deduplicate('auth', unexpected);
    expect(unexpected).not.toHaveBeenCalled();
    finishNew?.('new');
    await expect(newRequest).resolves.toBe('new');
    await expect(joined).resolves.toBe('new');
  });
});
