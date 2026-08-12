import axios from 'axios';
import { authenticateWithSkyward, parseAuthResponse } from '../../lib/api/skyward/auth';
import {
  fetchMessages,
  fetchMoreMessages,
  parseMessages,
  renderMessageBody,
} from '../../lib/api/skyward/messages';
import { safeMessageURL } from '../../lib/utils/message-links';

jest.mock('axios', () => ({
  __esModule: true,
  default: { post: jest.fn() },
}));

jest.mock('../../lib/utils/logger', () => ({
  logger: {
    debug: jest.fn(),
    info: jest.fn(),
    success: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
  Modules: { API_MESSAGES: 'API:Messages' },
  log: {
    api: {
      request: jest.fn(),
      success: jest.fn(),
      error: jest.fn(),
    },
  },
}));

const post = axios.post as jest.MockedFunction<typeof axios.post>;
const sessionCodes = {
  dwd: 'dwd',
  wfaacl: 'wfaacl',
  encses: 'encses',
  'User-Type': 'guardian',
  sessionid: 'session-one\x15session-two',
};

function authResponse(leadingEmptyTokens = 0): string {
  const tokens = [
    'dwd', 'session-one', 'session-two', 'wfaacl', 'unused-4', 'unused-5',
    'guardian', 'unused-7', 'unused-8', 'unused-9', 'unused-10', 'unused-11',
    'unused-12', 'unused-13', 'encses',
  ];
  return `<li>${'^'.repeat(leadingEmptyTokens)}${tokens.join('^')}</li>`;
}

describe('Skyward authentication response parsing', () => {
  it.each([0, 2])('uses one field layout with %i leading empty tokens', leadingEmptyTokens => {
    expect(parseAuthResponse(authResponse(leadingEmptyTokens))).toEqual(sessionCodes);
  });

  it('rejects a response without the expected wrapper', () => {
    expect(() => parseAuthResponse('dwd^session-one^session-two')).toThrow(
      /unsupported authentication response/
    );
  });
});

describe('Skyward request deadlines', () => {
  beforeEach(() => {
    post.mockReset();
    post.mockRejectedValue(new Error('stalled request'));
  });

  it('bounds credential verification', async () => {
    await expect(authenticateWithSkyward({
      username: 'student',
      password: 'password',
      baseURL: 'https://example.test/',
    })).rejects.toThrow('stalled request');

    expect(post.mock.calls[0][2]).toEqual(expect.objectContaining({ timeout: 30000 }));
  });

  it('bounds initial and background inbox loading', async () => {
    await expect(fetchMessages(sessionCodes, 'https://example.test/')).rejects.toThrow(
      'stalled request'
    );
    expect(post.mock.calls[0][2]).toEqual(expect.objectContaining({ timeout: 30000 }));
  });

  it('bounds inbox pagination', async () => {
    await expect(fetchMoreMessages(
      sessionCodes,
      'https://example.test/',
      'last-message'
    )).rejects.toThrow('stalled request');
    expect(post.mock.calls[0][2]).toEqual(expect.objectContaining({ timeout: 30000 }));
  });

  it('returns the initial inbox page without fetching older batches', async () => {
    post.mockResolvedValue({
      data: `<ul id="messageFeed"><li class="feedItem allowRemove">
        <div class="messageWrap message_general" data-wall-id="wall-1">
          <div class="messageHead"><div class="text"></div></div>
          <div class="messageBody"><div class="date">Aug 12</div><div class="text">
            <div class="Subject">Welcome</div><span id="messageText_1"></span>
          </div></div>
        </div>
      </li></ul>`,
    } as any);

    await expect(fetchMessages(sessionCodes, 'https://example.test/')).resolves.toHaveLength(1);
    expect(post).toHaveBeenCalledTimes(1);
  });
});

describe('Skyward inbox validation', () => {
  it('accepts an anchored empty inbox', () => {
    expect(parseMessages('<ul id="messageFeed"></ul>')).toEqual([]);
  });

  it.each([
    '<html><body>Maintenance</body></html>',
    '<ul id="messageFeed"><li class="feedItem allowRemove"><div class="messageWrap" data-wall-id="x"></div></li></ul>',
  ])('rejects arbitrary or structurally incomplete successful HTML', html => {
    expect(() => parseMessages(html)).toThrow(/message feed|structurally incomplete/);
  });

  it('activates only HTTPS links from remote message HTML', () => {
    expect(renderMessageBody(
      '<a href="javascript:alert(1)">Script</a> '
      + '<a href="elevate://settings">Settings</a> '
      + '<a href="https://school.example/path">Portal</a>'
    )).toBe('Script Settings [Portal](https://school.example/path)');
    expect(safeMessageURL('javascript:alert(1)')).toBeNull();
    expect(safeMessageURL('elevate://settings')).toBeNull();
    expect(safeMessageURL('https://school.example/path')).toBe('https://school.example/path');
  });
});
