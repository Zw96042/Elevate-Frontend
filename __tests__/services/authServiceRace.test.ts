import { AuthService } from '../../lib/services/auth-service';
import { authenticateWithSkyward } from '../../lib/api';
import { SkywardAuth } from '../../lib/skywardAuthInfo';
import { SessionManager } from '../../lib/utils/session-manager';
import { DeviceEventEmitter } from 'react-native';

jest.mock('../../lib/api', () => ({
  authenticateWithSkyward: jest.fn(),
}));

jest.mock('../../lib/skywardAuthInfo', () => ({
  SkywardAuth: { get: jest.fn() },
}));

jest.mock('../../lib/utils/session-manager', () => ({
  SessionManager: {
    saveSessionCodes: jest.fn(),
    clearSessionCodes: jest.fn(),
    hasValidSession: jest.fn(),
  },
}));

jest.mock('../../lib/utils/logger', () => ({
  logger: {
    debug: jest.fn(),
    info: jest.fn(),
    success: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    time: jest.fn(() => jest.fn()),
  },
  Modules: { AUTH: 'Auth', DEDUP: 'Dedup' },
  log: {
    api: {
      request: jest.fn(),
      success: jest.fn(),
      error: jest.fn(),
    },
    cache: { hit: jest.fn() },
  },
}));

const authenticate = authenticateWithSkyward as jest.MockedFunction<
  typeof authenticateWithSkyward
>;
const getCredentials = SkywardAuth.get as jest.MockedFunction<typeof SkywardAuth.get>;
const saveSession = SessionManager.saveSessionCodes as jest.MockedFunction<
  typeof SessionManager.saveSessionCodes
>;
const clearSession = SessionManager.clearSessionCodes as jest.MockedFunction<
  typeof SessionManager.clearSessionCodes
>;

const accountA = {
  link: 'https://example.test/',
  username: 'account-a',
  password: 'password-a',
};

const sessionA = {
  dwd: 'a-dwd',
  wfaacl: 'a-wfaacl',
  encses: 'a-encses',
  'User-Type': 'guardian',
  sessionid: 'a-session',
};

describe('AuthService account boundaries', () => {
  beforeEach(async () => {
    jest.clearAllMocks();
    clearSession.mockResolvedValue();
    saveSession.mockResolvedValue();
    getCredentials.mockResolvedValue(accountA);
    await AuthService.clearSession();
    jest.clearAllMocks();
    clearSession.mockResolvedValue();
    saveSession.mockResolvedValue();
    getCredentials.mockResolvedValue(accountA);
  });

  it('cannot restore a stale session after credentials are cleared', async () => {
    let finishLogin: ((session: typeof sessionA) => void) | undefined;
    authenticate.mockImplementation(
      () => new Promise(resolve => {
        finishLogin = resolve;
      })
    );

    const staleLogin = AuthService.authenticate();
    await Promise.resolve();
    await Promise.resolve();

    const clearing = AuthService.clearSession();
    finishLogin?.(sessionA);

    await expect(staleLogin).resolves.toEqual({
      success: false,
      error: 'Credentials changed during authentication',
    });
    await clearing;

    expect(saveSession).not.toHaveBeenCalled();
    expect(clearSession).toHaveBeenCalledTimes(1);
  });

  it('does not wait for a stalled Skyward request before clearing the session', async () => {
    let finishLogin: ((session: typeof sessionA) => void) | undefined;
    authenticate.mockImplementation(
      () => new Promise(resolve => {
        finishLogin = resolve;
      })
    );

    const staleLogin = AuthService.authenticate();
    await Promise.resolve();
    await Promise.resolve();

    await expect(AuthService.clearSession()).resolves.toBeUndefined();
    expect(clearSession).toHaveBeenCalledTimes(1);
    expect(saveSession).not.toHaveBeenCalled();

    finishLogin?.(sessionA);
    await expect(staleLogin).resolves.toEqual({
      success: false,
      error: 'Credentials changed during authentication',
    });
    expect(saveSession).not.toHaveBeenCalled();
  });

  it('sends former development credentials through real authentication', async () => {
    const developmentCredentials = {
      link: 'https://example.test/',
      username: 'dev-test',
      password: 'fgx',
    };
    getCredentials.mockResolvedValue(developmentCredentials);
    authenticate.mockResolvedValue(sessionA);

    await expect(AuthService.authenticate()).resolves.toEqual({ success: true });
    expect(authenticate).toHaveBeenCalledWith({
      username: developmentCredentials.username,
      password: developmentCredentials.password,
      baseURL: developmentCredentials.link,
    });
    expect(saveSession).toHaveBeenCalledWith(sessionA, developmentCredentials.link);
  });

  it('never reuses account A success after credentials become account B', async () => {
    const accountB = { ...accountA, username: 'account-b', password: 'password-b' };
    authenticate.mockResolvedValue(sessionA);
    await expect(AuthService.authenticate()).resolves.toEqual({ success: true });

    getCredentials.mockResolvedValue(accountB);
    await expect(AuthService.authenticate()).resolves.toEqual({ success: true });

    expect(authenticate).toHaveBeenCalledTimes(2);
    expect(authenticate).toHaveBeenLastCalledWith({
      username: accountB.username,
      password: accountB.password,
      baseURL: accountB.link,
    });
  });

  it('preserves the session and account UI on a transient network failure', async () => {
    const emit = jest.spyOn(DeviceEventEmitter, 'emit');
    authenticate.mockRejectedValue(Object.assign(new Error('timeout of 30000ms exceeded'), {
      name: 'AxiosError',
      code: 'ECONNABORTED',
    }));

    await expect(AuthService.authenticate()).resolves.toEqual({
      success: false,
      error: 'timeout of 30000ms exceeded',
    });
    expect(clearSession).not.toHaveBeenCalled();
    expect(emit).not.toHaveBeenCalledWith('credentialsInvalid');
    emit.mockRestore();
  });

  it('invalidates the session after an explicit credential rejection', async () => {
    const emit = jest.spyOn(DeviceEventEmitter, 'emit');
    authenticate.mockRejectedValue(new Error('Invalid username or password'));

    await expect(AuthService.authenticate()).resolves.toEqual({
      success: false,
      error: 'Invalid username or password',
    });
    expect(clearSession).toHaveBeenCalledTimes(1);
    expect(emit).toHaveBeenCalledWith('credentialsInvalid');
    emit.mockRestore();
  });
});
