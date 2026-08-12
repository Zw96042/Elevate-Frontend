import { act, renderHook, waitFor } from '@testing-library/react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useInboxCache } from '@/hooks/useInboxCache';
import { MessageService } from '@/lib/services';
import { invalidateAccountDataCache } from '@/lib/utils/account-data-cache';

jest.mock('@/lib', () => ({
  SkywardAuth: { hasCredentials: jest.fn(async () => true) },
}));

jest.mock('@/lib/services', () => ({
  MessageService: { loadMessages: jest.fn(), loadMoreMessages: jest.fn() },
}));

jest.mock('@react-native-async-storage/async-storage', () => ({
  __esModule: true,
  default: {
    getAllKeys: jest.fn(async () => []),
    multiRemove: jest.fn(async () => undefined),
    multiSet: jest.fn(async () => undefined),
    getItem: jest.fn(async () => null),
  },
}));

describe('Inbox request ownership', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);
  });

  it('releases loading when an ordinary cache clear invalidates the request', async () => {
    let finish!: (value: any) => void;
    (MessageService.loadMessages as jest.Mock).mockReturnValue(
      new Promise(resolve => { finish = resolve; })
    );
    const { result } = renderHook(() => useInboxCache());

    let loading!: Promise<void>;
    act(() => { loading = result.current.loadMessagesWithCache(true); });
    await waitFor(() => expect(result.current.loading).toBe(true));
    await act(async () => { await invalidateAccountDataCache(); });
    finish({ success: true, messages: [{ messageRowId: 'old-account' }] });
    await act(async () => { await loading; });

    expect(result.current.loading).toBe(false);
    expect(result.current.messages).toEqual([]);
    expect(AsyncStorage.multiSet).not.toHaveBeenCalled();
  });

  it('applies a changed equal-length first page over a larger cached inbox', async () => {
    const cached = [
      { messageRowId: 'old-first', subject: 'Old', date: '2026-08-11' },
      { messageRowId: 'older', subject: 'Older', date: '2026-08-10' },
    ];
    (AsyncStorage.getItem as jest.Mock).mockImplementation(async (key: string) => {
      if (key === 'cachedInboxTimestamp') return Date.now().toString();
      if (key === 'cachedInboxMessages') {
        return JSON.stringify({ messages: cached, lastUpdated: '', totalCount: 2 });
      }
      return null;
    });
    (MessageService.loadMessages as jest.Mock).mockResolvedValue({
      success: true,
      messages: [
        { messageRowId: 'new-first', subject: 'New', date: '2026-08-12' },
        { messageRowId: 'old-first', subject: 'Updated', date: '2026-08-11' },
      ],
    });
    const { result } = renderHook(() => useInboxCache());

    await act(async () => { await result.current.loadMessagesWithCache(false); });
    await waitFor(() => expect(result.current.messages[0]?.messageRowId).toBe('new-first'));

    expect(result.current.messages.map(message => message.messageRowId)).toEqual([
      'new-first', 'old-first', 'older',
    ]);
    expect(result.current.messages[1].subject).toBe('Updated');
    expect(AsyncStorage.multiSet).toHaveBeenCalled();
  });
});
