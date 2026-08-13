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
    timeout: 30000,
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
export function parseAuthResponse(postResponse: string): SkywardSessionCodes | null {
  if (!postResponse) return null;

  const response = postResponse.trim();
  const root = parse(response);
  const rootText = (root.text || response).toLowerCase();

  if (
    rootText.includes('invalid username or password') ||
    rootText.includes('invalid user') ||
    rootText.includes('invalid login')
  ) {
    throw new Error('Invalid username or password');
  }

  if (!response.startsWith('<li>') || !response.endsWith('</li>')) {
    throw new Error('Skyward returned an unsupported authentication response');
  }

  const dissectedString = response.substring(4, response.length - 5);
  const toks = dissectedString.split('^');

  // Find the first non-empty token to determine offset
  // Some responses have leading empty tokens (^^^^) which shifts all indices
  let offset = 0;
  while (offset < toks.length && toks[offset] === '') {
    offset++;
  }

  if (toks.length < offset + 15) {
    throw new Error('Skyward returned an unsupported authentication response');
  }

  const dwd = toks[offset];
  const sessionPart1 = toks[offset + 1];
  const sessionPart2 = toks[offset + 2];
  const wfaacl = toks[offset + 3];
  const userType = toks[offset + 6];
  const encses = toks[offset + 14];

  if (!dwd || !sessionPart1 || !sessionPart2 || !wfaacl || !userType || !encses) {
    throw new Error('Failed to extract session codes from Skyward response');
  }

  const sessionid = `${sessionPart1}\x15${sessionPart2}`;

  return {
    dwd,
    wfaacl,
    encses,
    'User-Type': userType,
    sessionid,
  };
}
