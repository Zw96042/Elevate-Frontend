// Skyward grades API
import axios from 'axios';
import { parse } from 'node-html-parser';
import { SkywardSessionCodes, GradeInfoParams, GradeInfoResult } from '../../types/api';
import { logger, Modules, log } from '../../utils/logger';

/**
 * Fetch detailed grade information for a specific course
 */
export async function fetchGradeInfo(
  params: GradeInfoParams,
  baseUrl: string,
  sessionCodes: SkywardSessionCodes
): Promise<GradeInfoResult> {
  const startTime = Date.now();
  const endpoint = 'sfgradebook001.w';
  log.api.request(Modules.API_GRADES, endpoint);
  logger.debug(Modules.API_GRADES, `Fetching grade info for course ${params.corNumId}, bucket ${params.bucket}`);

  try {
    const fullUrl = `${baseUrl}httploader.p?file=${endpoint}`;

    const postData = {
      action: 'viewGradeInfoDialog',
      gridCount: '1',
      fromHttp: 'yes',
      stuId: params.stuId,
      entityId: params.entityId || '',
      corNumId: params.corNumId,
      track: params.track || '',
      section: params.section,
      gbId: params.gbId,
      bucket: params.bucket,
      subjectId: params.subjectId || '',
      dialogLevel: params.dialogLevel || '',
      isEoc: params.isEoc || 'no',
      ishttp: 'true',
      sessionid: sessionCodes.sessionid,
      javascript: 'filesAdded=jquery.1.8.2.js,qsfmain001.css,sfgradebook.css,qsfmain001.min.js,sfgradebook.js,sfprint001.js',
      encses: sessionCodes.encses,
      dwd: sessionCodes.dwd,
      wfaacl: sessionCodes.wfaacl,
      requestId: Date.now().toString(),
    };

    const formDataString = Object.entries(postData)
      .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
      .join('&');

    const response = await axios.post(fullUrl, formDataString, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
      timeout: 30000,
    });

    const rawResponse = response.data;
    if (!rawResponse || typeof rawResponse !== 'string') {
      throw new Error('Invalid response received');
    }

    // Extract HTML from CDATA section
    const match = rawResponse.match(/<output><!\[CDATA\[(.*)\]\]><\/output>/s);
    const html = match && match[1] ? match[1] : rawResponse;

    const result = parseGradeInfoHTML(html);
    const duration = Date.now() - startTime;
    
    log.api.success(Modules.API_GRADES, endpoint, duration);
    logger.info(Modules.API_GRADES, `Parsed ${result.gradebook.length} categories with ${result.gradebook.reduce((sum, cat) => sum + cat.assignments.length, 0)} assignments`);
    
    return result;
  } catch (error) {
    const duration = Date.now() - startTime;
    log.api.error(Modules.API_GRADES, endpoint, duration, error);
    throw error;
  }
}

/**
 * Parse grade info HTML into structured data
 */
function parseGradeInfoHTML(html: string): GradeInfoResult {
  // Check for session expiration
  if (typeof html === 'string' && html.match(/<data><!\[CDATA\[\s*\]\]><\/data>/)) {
    const err = new Error('Session expired');
    (err as any).code = 'SESSION_EXPIRED';
    throw err;
  }

  const root = parse(html);
  
  const clean = (txt = "") => txt.replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();
  const toInt = (txt: string) => {
    const m = clean(txt).match(/^-?\d+/);
    return m ? parseInt(m[0], 10) : null;
  };
  const toFloat = (txt: string) => {
    const m = clean(txt).match(/-?\d+(?:\.\d+)?/);
    return m ? parseFloat(m[0]) : null;
  };

  // Extract course info
  const courseLink = root.querySelector("h2.gb_heading a");
  const periodText = root.querySelector("h2.gb_heading span.fXs b")?.textContent;
  const instructorLinks = root.querySelectorAll("h2.gb_heading a");
  const instructorLink = instructorLinks.length > 1 ? instructorLinks[1] : null;
  
  const course = clean(courseLink?.textContent || "");
  const period = toInt(periodText || "");
  const instructor = clean(instructorLink?.textContent || "");

  // Extract lit info
  let litHeader = root.querySelector("table[id^='grid_stuTermSummaryGrid'] thead th");
  if (!litHeader) {
    const termGrid = root.querySelector("div[id*='stuTermSummaryGrid']");
    if (termGrid) {
      litHeader = termGrid.querySelector("thead th") || termGrid.querySelector("th");
    }
  }
  
  const litHeaderText = clean(litHeader?.childNodes?.[0]?.textContent || litHeader?.textContent || "");
  const litName = litHeaderText.replace(/Grade\s*$/, "").trim();
  const dateMatch = (litHeader?.querySelector("span")?.textContent || "").match(/(\d{2}\/\d{2}\/\d{4})\s*-\s*(\d{2}\/\d{2}\/\d{4})/);
  
  const lit = {
    name: litName,
    begin: dateMatch ? dateMatch[1] : null,
    end: dateMatch ? dateMatch[2] : null,
  };

  // Extract summary score
  let summaryRow = root.querySelector("table[id^='grid_stuTermSummaryGrid'] tbody tr[class]:not(.sf_Section)");
  if (!summaryRow) {
    const termGrid = root.querySelector("div[id*='stuTermSummaryGrid']");
    if (termGrid) {
      summaryRow = termGrid.querySelector("tbody tr[class]:not(.sf_Section)") || termGrid.querySelector("tbody tr");
    }
  }
  
  const topScore = toFloat(summaryRow?.querySelector("td:last-child")?.textContent || "");
  const topGrade = topScore != null ? Math.round(topScore) : null;

  // Parse gradebook categories and assignments
  const gradebook = parseGradebook(root);

  return {
    course,
    instructor,
    lit,
    period,
    score: topScore,
    grade: topGrade,
    gradebook,
  };
}

/**
 * Parse gradebook categories and assignments
 */
function parseGradebook(root: any): any[] {
  const gradebook: any[] = [];
  
  let rows = [...root.querySelectorAll("table[id^='grid_stuAssignmentSummaryGrid'] tbody tr")];
  
  if (rows.length === 0) {
    const assignmentGrid = root.querySelector("div[id*='stuAssignmentSummaryGrid']");
    if (assignmentGrid) {
      rows = [...assignmentGrid.querySelectorAll("tr")];
    }
  }
  
  if (rows.length === 0) {
    const allTrs = root.querySelectorAll("tr");
    rows = [...allTrs].filter((tr: any) => 
      tr.querySelector("a[id='showAssignmentInfo']") || 
      (tr.classList.contains("sf_Section") && tr.classList.contains("cat"))
    );
  }
  
  let currentCategory: any = null;
  let lastMainCategory: any = null;
  let afterBoldCategory = false;

  const clean = (txt = "") => txt.replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();
  const toInt = (txt: string) => {
    const m = clean(txt).match(/^-?\d+/);
    return m ? parseInt(m[0], 10) : null;
  };
  const toFloat = (txt: string) => {
    const m = clean(txt).match(/-?\d+(?:\.\d+)?/);
    return m ? parseFloat(m[0]) : null;
  };

  rows.forEach((row: any) => {
    if (row.classList.contains("sf_Section") && row.classList.contains("cat")) {
      const cells = row.querySelectorAll("td");
      const nameNode = cells[1]?.childNodes?.[0];
      const rawName = clean(nameNode?.textContent || cells[1]?.textContent || "");
      
      const styleAttr = cells[1]?.getAttribute("style") || "";
      const isBold = /font-weight:\s*bold/i.test(styleAttr);
      
      let weightMatch: RegExpMatchArray | null = null;
      const spans = cells[1]?.querySelectorAll("span") || [];
      for (const span of spans) {
        const txt = clean(span.textContent || "");
        const match = txt.match(/weighted at ([\d.]+)%(?:, adjusted to ([\d.]+)%)?/i);
        if (match) {
          weightMatch = match;
          break;
        }
      }
      
      if (isBold) {
        lastMainCategory = {
          category: rawName,
          weight: null,
          adjustedWeight: null,
          assignments: [],
        };
        afterBoldCategory = true;
        if (weightMatch) {
          lastMainCategory.weight = parseFloat(weightMatch[1]);
          lastMainCategory.adjustedWeight = weightMatch[2] ? parseFloat(weightMatch[2]) : null;
        }
        gradebook.push(lastMainCategory);
        currentCategory = lastMainCategory;
        return;
      }

      if (/RC\d/i.test(rawName) && afterBoldCategory) {
        if (/RC1/i.test(rawName) && weightMatch && lastMainCategory && lastMainCategory.weight == null) {
          lastMainCategory.weight = parseFloat(weightMatch[1]);
          lastMainCategory.adjustedWeight = weightMatch[2] ? parseFloat(weightMatch[2]) : null;
        }
        return;
      }

      currentCategory = {
        category: rawName,
        weight: weightMatch ? parseFloat(weightMatch[1]) : null,
        adjustedWeight: weightMatch && weightMatch[2] ? parseFloat(weightMatch[2]) : null,
        assignments: [],
      };
      gradebook.push(currentCategory);
      afterBoldCategory = false;
      return;
    }

    const link = row.querySelector("a#showAssignmentInfo");
    if (link && currentCategory) {
      const cells = row.querySelectorAll("td");
      const date = clean(cells[0]?.textContent || "");
      const name = clean(link.textContent || "");
      const assignmentGrade = toInt(cells[2]?.textContent || "");
      const assignmentScore = toFloat(cells[3]?.textContent || "");
      const pointsText = clean(cells[4]?.textContent || "");
      
      let points: { earned: number; total: number } | null = null;
      const pm = pointsText.match(/(-?\d+(?:\.\d+)?)\s*out of\s*(-?\d+(?:\.\d+)?)/i);
      if (pm) {
        points = { earned: parseFloat(pm[1]), total: parseFloat(pm[2]) };
      }
      
      const meta: { type: string; note: string }[] = [];
      
      const missingTooltip = cells[5]?.getAttribute('tooltip');
      if (missingTooltip) {
        meta.push({ type: "missing", note: missingTooltip });
      }
      
      const noCountTooltip = cells[6]?.getAttribute('tooltip');
      if (noCountTooltip) {
        meta.push({ type: "noCount", note: noCountTooltip });
      }
      
      const absentTooltip = cells[7]?.getAttribute('tooltip');
      const absentText = cells[7]?.textContent?.trim() || '';
      
      if (absentTooltip) {
        meta.push({ type: "absent", note: absentTooltip });
      } else if (absentText && absentText !== '' && absentText !== '\u00A0' && !absentText.includes('out of')) {
        meta.push({ type: "absent", note: absentText });
      }
      
      currentCategory.assignments.push({
        date,
        name,
        grade: assignmentGrade,
        score: assignmentScore,
        points,
        meta,
      });
    }
  });

  return gradebook.filter(cat => !(cat.weight === 0 && (!cat.assignments || cat.assignments.length === 0)));
}
