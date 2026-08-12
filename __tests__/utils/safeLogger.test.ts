import { safeErrorDetails } from '../../lib/utils/logger';

describe('safe error logging', () => {
  it('never serializes Axios request credentials or session tokens', () => {
    const details = safeErrorDetails({
      name: 'AxiosError',
      message: 'Request failed with status code 500',
      code: 'ERR_BAD_RESPONSE',
      config: {
        data: 'login=secret-user&password=secret-password&dwd=secret-session',
        headers: { Cookie: 'sessionid=secret-cookie' },
      },
      response: { status: 500, data: 'secret-response' },
    });

    expect(details).toEqual({
      name: 'AxiosError',
      code: 'ERR_BAD_RESPONSE',
      status: 500,
    });
    expect(JSON.stringify(details)).not.toMatch(/secret-user|secret-password|secret-session|secret-cookie|secret-response/);
  });
});
