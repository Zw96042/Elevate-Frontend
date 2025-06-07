const config = require('./development.config.js');

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

    const res = await fetch(`${config.BACKEND_IP}/messages`, {
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
    // console.log(JSON.stringify(res));
    // console.log(res.status);
    if (res.status === 401) {
        // console.log("Session Expired");
        throw new Error(`Session Expired`);
    } else {
        // console.log("Unable to feetch");
        throw new Error(`Failed to fetch messages: ${res}`);
    }
  }

  const data = await res.json();
//   console.log("data:", data);

  if (data.error) throw new Error(data.error);

  return data;
};

export const fetchMoreSkywardMessages = async (
  sessionCodes: {
    dwd: string;
    wfaacl: string;
    encses: string;
    userType?: string;
    sessionid: string;
    baseUrl: string;
  },
  lastMessageId: string,
  limit: number
): Promise<Message[]> => {
    const response = await fetch(`${config.BACKEND_IP}/next-measdfssages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
        ...sessionCodes,
        lastMessageId,
        limit,
        }),
    });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Failed to fetch messages: ${text}`);
  }

  return await response.json();
};