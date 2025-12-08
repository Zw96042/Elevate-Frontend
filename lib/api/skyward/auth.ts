// Skyward authentication API
import axios from 'axios';
import { parse } from 'node-html-parser';
import { SkywardSessionCodes, SkywardCredentials } from '../../types/api';

/**
 * Authenticate with Skyward and get session codes
 */
export async function authenticateWithSkyward(
  credentials: SkywardCredentials
): Promise<SkywardSessionCodes> {
  const { username, password, baseURL } = credentials;

  if (!baseURL || typeof baseURL !== 'string') {
    throw new Error('Invalid baseURL provided');
  }

  const cleanBaseURL = baseURL.endsWith('/') ? baseURL : baseURL + '/';
  const authenticationURL = cleanBaseURL + 'skyporthttp.w';

  try {
    new URL(authenticationURL);
  } catch (error) {
    throw new Error(`Invalid authentication URL: ${authenticationURL}`);
  }

  const formData = new URLSearchParams({
    codeType: 'tryLogin',
    login: username,
    password: password,
    requestAction: 'eel',
  });

  const response = await axios.post(authenticationURL, formData.toString(), {
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  });

  const parsed = parseAuthResponse(response.data);
  if (!parsed) {
    throw new Error('Failed to parse Skyward session codes.');
  }

  return parsed;
}

/**
 * Parse login response string
 */
function parseAuthResponse(postResponse: string): SkywardSessionCodes | null {
  if (!postResponse) return null;

  const dissectedString = postResponse.substring(4, postResponse.length - 5);
  const toks = dissectedString.split('^');

  if (toks.length < 15) {
    const root = parse(postResponse);
    const rootText = (root.text || postResponse || '').toLowerCase();

    if (
      rootText.includes('invalid username or password') ||
      rootText.includes('invalid user') ||
      rootText.includes('invalid login')
    ) {
      throw new Error('Invalid username or password');
    }

    throw new Error(`Authentication parsing failed: ${rootText || 'Unknown error'}`);
  }

  return {
    dwd: toks[0],
    wfaacl: toks[3],
    encses: toks[14],
    'User-Type': toks[6],
    sessionid: `${toks[1]}\x15${toks[2]}`,
  };
}
