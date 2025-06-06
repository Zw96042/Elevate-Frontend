export interface Message {
  from: string;
  className: string;
  date: string;
  subject: string;
  content: string;
}

/**
 * Fetches messages from your backend API and parses them
 * @param user Skyward username
 * @param pass Skyward password
 * @param baseUrl Skyward base URL
 */
export async function fetchSkywardMessages(
  user: string,
  pass: string,
  baseUrl: string
): Promise<Message[]> {
  const response = await fetch('http://192.168.1.136:3000/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ user, pass, baseUrl }),
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch messages: ${response.statusText}`);
  }

  return response.json(); // JSON with subject, from, date, etc.
}