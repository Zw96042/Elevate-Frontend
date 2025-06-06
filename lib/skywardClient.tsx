export const fetchSkywardMessages = async ({
  dwd, wfaacl, encses, userType, sessionid, baseUrl
}: {
  dwd: string,
  wfaacl: string,
  encses: string,
  userType?: string,
  sessionid: string,
  baseUrl: string,
}) => {
  if (!sessionid || !encses || !dwd || !wfaacl || !baseUrl) {
    throw new Error('Missing session credentials');
  }

  const res = await fetch('http://192.168.1.136:3000/messages', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      sessionid,
      encses,
      dwd,
      wfaacl,
      baseUrl,
      'User-Type': userType,
    }),
  });

  if (!res.ok) {
    throw new Error(`Failed to fetch messages: ${res.statusText}`);
  }

  const data = await res.json();

  if (data.error) throw new Error(data.error);

  return data;
};