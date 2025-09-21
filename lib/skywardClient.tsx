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

  if (sessionid != "dev" || encses != "dev" || dwd != "dev" || wfaacl != "dev") {
    try {
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

      // Always try to parse the response first
      let data;
      let responseText = '';
      
      try {
        responseText = await res.text();
        data = JSON.parse(responseText);
      } catch (parseError) {
        // If we can't parse JSON, treat as error
        throw new Error(`Failed to parse messages response: ${res.status} ${res.statusText} - ${responseText}`);
      }

      // Check if we got valid data regardless of status code
      if (data && (data.success !== false) && Array.isArray(data)) {
        return data;
      }

      // Only throw errors if we don't have valid data
      if (!res.ok) {
        if (res.status === 401) {
            throw new Error(`Session Expired`);
        } else {
            throw new Error(`Failed to fetch messages: ${res.status} ${res.statusText} - ${responseText}`);
        }
      }

      // If response is ok but data indicates failure
      if (data && data.success === false) {
        throw new Error(data.error || 'Messages API returned failure status');
      }

      return data;
    } catch (networkError: any) {
      // If it's a fetch network error, check if we can still get data
      console.error('❌ Network error fetching messages:', networkError.message);
      throw networkError;
    }
  } else {
    return EMAILS;
  }
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
    const response = await fetch(`${config.BACKEND_IP}/next-messages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
        ...sessionCodes,
        lastMessageId,
        limit,
        }),
    });

  // Always try to parse the response first
  let data;
  let responseText = '';
  
  try {
    responseText = await response.text();
    data = JSON.parse(responseText);
  } catch (parseError) {
    // If we can't parse JSON, treat as error
    throw new Error(`Failed to parse next messages response: ${response.status} ${response.statusText} - ${responseText}`);
  }

  // Check if we got valid data regardless of status code
  if (data && (data.success !== false) && Array.isArray(data)) {
    return data;
  }

  // Only throw errors if we don't have valid data
  if (!response.ok) {
    if (response.status === 401) {
      throw new Error(`Session Expired`);
    } else {
      throw new Error(`Failed to fetch next messages: ${response.status} ${response.statusText} - ${responseText}`);
    }
  }

  // If response is ok but data indicates failure
  if (data && data.success === false) {
    throw new Error(data.error || 'Next messages API returned failure status');
  }

  return data;
};

const EMAILS = [
  {
    "className": "Administrator",
    "content": "**Schedule Change Alert:**\n\nThe start time for 2nd period has been moved to 9:00 AM. **Please review the new bell schedule** before tomorrow.\n\nView details here: [Updated Bell Schedule](https://district.wisd.org/schedule).",
    "date": "Fri Jul 18, 2025  6:00pm",
    "from": "Administrator",
    "messageRowId": "0x00000000031a1001",
    "subject": "Semester Bell Schedule Update"
  },
  {
    "className": "Honors Biology",
    "content": "**Lab Reminder:**\n\nLab coats and safety goggles are required for Monday’s dissection. **Be sure to complete the pre-lab quiz** in Google Classroom.\n\nAccess the quiz here: [Pre-Lab Quiz](https://classroom.google.com/prelab).",
    "date": "Fri Jul 18, 2025  4:15pm",
    "from": "Ms. Nguyen",
    "messageRowId": "0x00000000031a1002",
    "subject": "Dissection Lab Prep"
  },
  {
    "className": "Student Council",
    "content": "**Vote Today!**\n\nHelp decide this year’s Spring Fling theme. **Your opinion matters**!\n\nCast your vote here: [Theme Selection Poll](https://whs-stuco.org/vote2025).",
    "date": "Thu Jul 17, 2025  3:30pm",
    "from": "Student Council",
    "messageRowId": "0x00000000031a1003",
    "subject": "Spring Fling Theme Voting Is Open"
  },
  {
    "className": "Counseling Office",
    "content": "**College Night Registration**\n\nJoin us on August 5 for a live Q&A with UT and A&M admissions. **Seats are limited**—RSVP now.\n\nSign up: [Reserve Your Spot](https://whs-counseling.org/college-night).",
    "date": "Thu Jul 17, 2025  9:00am",
    "from": "Counseling Office",
    "messageRowId": "0x00000000031a1004",
    "subject": "Register for College Info Night"
  },
  {
    "className": "Theater Dept",
    "content": "**Fall Play Auditions**\n\nAudition packets and character breakdowns are available. **Submit your application by Monday**.\n\nDownload packet: [Audition Materials](https://whs-theater.org/auditions).",
    "date": "Wed Jul 16, 2025  5:45pm",
    "from": "Mr. Delgado",
    "messageRowId": "0x00000000031a1005",
    "subject": "Sign Up: Fall Play Auditions"
  },
  {
    "className": "Administrator",
    "content": "**Device Check-In Required**\n\nAll students must return their school laptops by July 22. **Failure to comply may incur fees**.\n\nSubmit your return form here: [Laptop Return](https://district.wisd.org/device-checkin).",
    "date": "Wed Jul 16, 2025  2:10pm",
    "from": "Administrator",
    "messageRowId": "0x00000000031a1006",
    "subject": "School Laptop Return Notice"
  },
  {
    "className": "NHS",
    "content": "**Volunteer Hours Deadline**\n\nAll National Honor Society volunteer logs are due this Friday at noon. **No late submissions accepted**.\n\nUpload your hours: [Submit Hours](https://whs-nhs.org/hours).",
    "date": "Tue Jul 15, 2025  11:20am",
    "from": "NHS",
    "messageRowId": "0x00000000031a1007",
    "subject": "Submit NHS Volunteer Hours"
  },
  {
    "className": "Robotics Team 2468",
    "content": "**Kickoff Meeting Slides**\n\nOur 2025 build season slides are ready. **Please review before this weekend’s workshop**.\n\nView slides: [Team 2468 Docs](https://team2468.org/kickoff2025).",
    "date": "Tue Jul 15, 2025  8:45am",
    "from": "Robotics Team 2468",
    "messageRowId": "0x00000000031a1008",
    "subject": "2025 Build Season Kickoff Materials"
  }
]

export const fetchSkywardReportCard = async ({
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

  const requestBody = {
    sessionid,
    encses,
    dwd,
    wfaacl,
    baseUrl,
    'User-Type': userType || '2',
  };

  // console.log('📡 Fetching report card with:');
  // console.log('Backend URL:', `${config.BACKEND_IP}/scrape-report`);
  // console.log('Request body:', JSON.stringify(requestBody, null, 2));

  try {
    const res = await fetch(`${config.BACKEND_IP}/scrape-report`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(requestBody),
    });

    // Always try to parse the response first
    let data;
    let responseText = '';
    
    try {
      responseText = await res.text();
      data = JSON.parse(responseText);
    } catch (parseError) {
      // If we can't parse JSON, treat as error
      throw new Error(`Failed to parse response: ${res.status} ${res.statusText} - ${responseText}`);
    }

    // Check if we got valid data regardless of status code
    if (data && (data.success !== false)) {
      return data;
    }

    // Only throw errors if we don't have valid data
    if (!res.ok) {
      if (res.status === 401) {
        throw new Error(`Session Expired`);
      } else {
        throw new Error(`Failed to fetch report card: ${res.status} ${res.statusText} - ${responseText}`);
      }
    }

    // If response is ok but data indicates failure
    if (data && data.success === false) {
      throw new Error(data.error || 'API returned failure status');
    }

    return data;
  } catch (error: any) {
    throw error;
  }
};