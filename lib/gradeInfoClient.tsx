// gradeInfoClient.tsx
// Handles calling the backend /grade-info API and returns grade info for a class



export interface GradeInfoParams {
  stuId: string;
  corNumId: string;
  section: string;
  gbId: string;
  bucket: string;
  customUrl?: string;
}

export async function fetchGradeInfo(sessionTokens: any, params: GradeInfoParams) {
  const config = require('./development.config.js');
  const response = await fetch(`${config.BACKEND_IP}/grade-info`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionTokens, params }),
  });
  console.log("Grade info response status:", response.body);
  return await response.json();
}
