// Skyward academic history API
import axios from 'axios';
import { parse } from 'node-html-parser';
import { SkywardSessionCodes } from '../../types/api';
import { parseJavaScriptLiteral } from '../../utils/javascript-literal-parser';
import { logger, Modules, log } from '../../utils/logger';

/**
 * Fetch and parse academic history from Skyward
 */
export async function fetchAcademicHistory(
  baseUrl: string,
  sessionCodes: SkywardSessionCodes
): Promise<any> {
  const startTime = Date.now();
  logger.debug(Modules.API_HISTORY, 'Fetching academic history');
  
  try {
    const html = await scrapeAcademicHistoryHTML(baseUrl, sessionCodes);
    const gridObjects = parseAcademicHistoryHTML(html);
    const result = gridObjects === null ? {} : condenseAcademicHistory(gridObjects);
    
    const duration = Date.now() - startTime;
    const yearCount = Object.keys(result).filter(k => k !== 'alt').length;
    logger.success(Modules.API_HISTORY, `Loaded ${yearCount} academic years (${duration}ms)`);
    
    return result;
  } catch (error) {
    const duration = Date.now() - startTime;
    logger.error(Modules.API_HISTORY, `Failed to fetch academic history (${duration}ms)`, error);
    throw error;
  }
}

/**
 * Fetch gradebook HTML from Skyward
 */
export async function fetchGradebookHTML(
  baseUrl: string,
  sessionCodes: SkywardSessionCodes
): Promise<string> {
  const startTime = Date.now();
  log.api.request(Modules.API_HISTORY, 'sfgradebook001.w');
  
  try {
    const postData = new URLSearchParams({ ...sessionCodes });
    const gradebookUrl = baseUrl + 'sfgradebook001.w';

    const response = await axios.post(gradebookUrl, postData.toString(), {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      },
      timeout: 10000,
      maxRedirects: 2,
      validateStatus: (status) => status >= 200 && status < 300,
    });

    const htmlData = response.data;

    if (htmlData.includes('Your session has expired') || htmlData.includes('Your session has timed out')) {
      const err = new Error('Session expired');
      (err as any).code = 'SESSION_EXPIRED';
      throw err;
    }

    const duration = Date.now() - startTime;
    log.api.success(Modules.API_HISTORY, 'sfgradebook001.w', duration);
    
    return htmlData;
  } catch (error) {
    const duration = Date.now() - startTime;
    log.api.error(Modules.API_HISTORY, 'sfgradebook001.w', duration, error);
    throw error;
  }
}

/**
 * Parse gradebook HTML to extract course data
 */
export async function parseGradebookHTML(htmlData: string): Promise<any> {
  const root = parse(htmlData);

  const scripts = root.querySelectorAll('script');
  let scriptContent = '';

  for (const script of scripts) {
    const content = script.innerHTML;
    if (content && content.includes('sf_gridObjects')) {
      scriptContent = content;
      break;
    }
  }

  if (!scriptContent) {
    throw new Error('Skyward gradebook response had no grid data');
  }

  const results = /\$\.extend\(\(sff\.getValue\('sf_gridObjects'\) \|\| {}\), ([\s\S]*)\)\);/g.exec(scriptContent);

  if (!results) {
    throw new Error('Skyward gradebook response had an invalid grid script');
  }

  const parsedData = parseJavaScriptLiteral(results[1]);
  if (!parsedData || typeof parsedData !== 'object' || Array.isArray(parsedData)) {
    throw new Error('Skyward gradebook data had an invalid format');
  }
  const values = Object.entries(parsedData);
  const targetPair = values.find(([key]) => /stuGradesGrid_\d+_\d+/.test(key));

  if (!targetPair) {
    throw new Error('Skyward gradebook response had no compatible student grid');
  }

  const gridData = targetPair[1] as any;
  if (!gridData.tb || !Array.isArray(gridData.tb.r)) {
    throw new Error('Skyward gradebook response had an incomplete student grid');
  }
  const rows = gridData.tb.r;
  const courseRows = rows.filter(
    (row: any) => Array.isArray(row?.c) && row.c.length > 0 && row.c[0]?.cId
  );
  if (rows.length > 0 && courseRows.length === 0) {
    throw new Error('Skyward gradebook contained unrecognized populated rows');
  }

  // Extract course details
  const courseDetails: any = {};

  root.querySelectorAll('table[id*="classDesc_"]').forEach(table => {
    const tableId = table.getAttribute('id') || '';
    const idMatch = /classDesc_(\d+)_(\d+)_0_(\d+)/.exec(tableId);

    if (idMatch) {
      const stuId = idMatch[1];
      const corNumId = Number(idMatch[2]);
      const section = idMatch[3];

      const courseName = table.querySelector('span.bld.classDesc a')?.text?.trim() || '';
      const instructorElement = table.querySelector('tr:last-child td a');
      const instructorName = instructorElement?.text?.trim() || '';

      const periodRow = table.querySelector('tr:nth-child(2) td');
      const periodText = periodRow?.text || '';
      const periodMatch = /Period\s*(\d+)/.exec(periodText);
      const period = periodMatch ? Number(periodMatch[1]) : null;

      const timeSpan = periodRow?.querySelector('span.fXs.fWn');
      const timeText = timeSpan?.text || '';
      const timeMatch = /\(([^)]+)\)/.exec(timeText);
      const time = timeMatch ? timeMatch[1] : null;

      courseDetails[corNumId] = {
        courseName,
        instructor: instructorName,
        period,
        time,
        stuId,
        corNumId,
        section,
      };
    }
  });

  // Process grade data
  const courses = courseRows
    .map((row: any) => {
      const courseData: any[] = [];
      let courseNumber: number | null = null;
      let gbID: string | null = null;

      row.c.forEach((cell: any) => {
        if (cell.h) {
          const cellRoot = parse(cell.h);
          const element = cellRoot.querySelector('a');

          if (element) {
            const course = Number(element.getAttribute('data-cni'));
            const bucket = element.getAttribute('data-bkt');
            const scoreText = element.text?.trim() || '';

            if (course && !gbID) {
              const gId = element.getAttribute('data-gid');
              if (gId) {
                gbID = gId;
              }
            }

            if (course && bucket) {
              courseNumber = course;
              const score = Number(scoreText);
              if (scoreText.length > 0 && Number.isFinite(score)) {
                courseData.push({ bucket, score });
              }
            }
          }
        }
      });

      if (courseNumber) {
        const details = courseDetails[courseNumber] || {};

        return {
          course: courseNumber,
          courseName: details.courseName || 'Unknown Course',
          instructor: details.instructor || 'Unknown Instructor',
          period: details.period || 0,
          time: details.time || null,
          semester: 'both' as const,
          scores: courseData,
          stuId: details.stuId,
          corNumId: details.corNumId,
          section: details.section,
          gbId: gbID,
        };
      }

      throw new Error('Skyward gradebook course row was structurally incomplete');
    })
    .filter((course: any) => course !== null);

  return { data: courses, raw: htmlData };
}

/**
 * Combine academic history with current gradebook data
 */
export function combineAcademicData(
  academicHistory: any,
  gradebookData: any,
  fallbackGrade?: number
): any {
  if (!gradebookData || !gradebookData.data || gradebookData.data.length === 0) {
    return academicHistory;
  }

  const yearKeys = Object.keys(academicHistory).filter(k => k !== 'alt');
  let latestYear: string;
  let yearData: any;

  if (yearKeys.length === 0) {
    latestYear = 'current';
    yearData = { grade: fallbackGrade, courses: {} };
  } else {
    const existingLatestYear = yearKeys.sort().reverse()[0];
    const existingYearData = academicHistory[existingLatestYear];
    if (fallbackGrade !== undefined && existingYearData?.grade !== fallbackGrade) {
      latestYear = nextAcademicYearKey(existingLatestYear, new Set(yearKeys));
      yearData = { grade: fallbackGrade, courses: {} };
    } else {
      latestYear = existingLatestYear;
      yearData = existingYearData;
    }
  }

  if (!yearData || !yearData.courses) {
    throw new Error('Skyward academic history had an incomplete current year');
  }

  const academicCourses = yearData.courses;
  const bucketMap: any = {
    'TERM 1': 'pr1', 'TERM 2': 'pr2', 'TERM 3': 'rc1',
    'TERM 4': 'pr3', 'TERM 5': 'pr4', 'TERM 6': 'rc2',
    'TERM 7': 'pr5', 'TERM 8': 'pr6', 'TERM 9': 'rc3',
    'TERM 10': 'pr7', 'TERM 11': 'pr8', 'TERM 12': 'rc4',
    'SEM 1': 'sm1', 'SEM 2': 'sm2',
  };

  const mergedCourses: any = { ...academicCourses };
  const claimedAcademicKeys = new Set<string>();

  for (const gradebookCourse of gradebookData.data) {
    const lookupKey = normalizeCourseName(gradebookCourse.courseName);
    const academicKey = Object.keys(academicCourses).find(k => {
      if (claimedAcademicKeys.has(k)) return false;
      const course = academicCourses[k];
      if (
        gradebookCourse.corNumId !== undefined &&
        String(course.corNumId ?? '') === String(gradebookCourse.corNumId) &&
        String(course.section ?? '') === String(gradebookCourse.section ?? '')
      ) {
        return true;
      }
      return normalizeCourseName(course.courseName || k) === lookupKey;
    });
    const baseCourse = academicKey ? academicCourses[academicKey] : null;
    if (academicKey) claimedAcademicKeys.add(academicKey);

    const courseObj = baseCourse ? { ...baseCourse } : {
      terms: gradebookCourse.semester === 'both' ? '1 - 4' : '',
      finalGrade: '',
      sm1: null, sm2: null,
      pr1: '', pr2: '', pr3: '', pr4: '', pr5: '', pr6: '', pr7: '', pr8: '',
      rc1: '', rc2: '', rc3: '', rc4: '', ex1: '', ex2: '',
    };

    courseObj.courseId = gradebookCourse.course;
    courseObj.instructor = gradebookCourse.instructor;
    courseObj.period = gradebookCourse.period;
    if (gradebookCourse.time) courseObj.time = gradebookCourse.time;

    courseObj.stuId = gradebookCourse.stuId;
    courseObj.corNumId = gradebookCourse.corNumId;
    courseObj.section = gradebookCourse.section;
    courseObj.gbId = gradebookCourse.gbId;

    if (Array.isArray(gradebookCourse.scores)) {
      for (const scoreObj of gradebookCourse.scores) {
        const bucket = scoreObj.bucket;
        const field = bucketMap[bucket];
        if (field && field !== 'ex1' && field !== 'ex2') {
          courseObj[field] = scoreObj.score;
        }
      }
    }

    if (baseCourse) {
      courseObj.ex1 = baseCourse.ex1;
      courseObj.ex2 = baseCourse.ex2;
    }

    courseObj.courseName = gradebookCourse.courseName;
    const storageKey = academicKey || uniqueCourseKey(
      gradebookCourse.courseName,
      new Set(Object.keys(mergedCourses))
    );
    mergedCourses[storageKey] = courseObj;
  }

  return {
    ...academicHistory,
    [latestYear]: { ...yearData, courses: mergedCourses },
  };
}

function normalizeCourseName(name: string): string {
  return String(name || '').replace(/_\d+$/, '').trim().toUpperCase();
}

function uniqueCourseKey(courseName: string, existingKeys: Set<string>): string {
  if (!existingKeys.has(courseName)) return courseName;
  let suffix = 2;
  while (existingKeys.has(`${courseName}_${suffix}`)) suffix += 1;
  return `${courseName}_${suffix}`;
}

function nextAcademicYearKey(latestYear: string, existingKeys: Set<string>): string {
  const match = /^(\d{4})-(\d{4})$/.exec(latestYear);
  if (!match) {
    let suffix = 1;
    let candidate = 'current';
    while (existingKeys.has(candidate)) {
      suffix += 1;
      candidate = `current-${suffix}`;
    }
    return candidate;
  }

  let start = Number(match[2]);
  let candidate = `${start}-${start + 1}`;
  while (existingKeys.has(candidate)) {
    start += 1;
    candidate = `${start}-${start + 1}`;
  }
  return candidate;
}

export function inferGradeLevelFromHTML(html: string): number | undefined {
  const text = parse(html).text;
  const match = /\bGrade\s*(9|10|11|12)\b/i.exec(text)
    || /\b(9|10|11|12)(?:st|nd|rd|th)\s+Grade\b/i.exec(text);
  return match ? Number(match[1]) : undefined;
}

/**
 * Fetch combined academic history and gradebook data
 */
export async function fetchCombinedAcademicData(
  baseUrl: string,
  sessionCodes: SkywardSessionCodes
): Promise<any> {
  const startTime = Date.now();
  logger.info(Modules.API_HISTORY, 'Fetching combined academic data (parallel)');
  
  try {
    const [academicHistory, gradebookHtml] = await Promise.all([
      fetchAcademicHistory(baseUrl, sessionCodes),
      fetchGradebookHTML(baseUrl, sessionCodes),
    ]);
    const gradebookData = await parseGradebookHTML(gradebookHtml);
    const result = combineAcademicData(
      academicHistory,
      gradebookData,
      inferGradeLevelFromHTML(gradebookHtml)
    );
    
    const duration = Date.now() - startTime;
    logger.success(Modules.API_HISTORY, `Combined academic data loaded (${duration}ms)`);
    
    return result;
  } catch (error: any) {
    const duration = Date.now() - startTime;
    logger.error(Modules.API_HISTORY, `Failed to fetch combined data (${duration}ms)`, error);
    throw error;
  }
}

// Private helper functions

function scrapeAcademicHistoryHTML(baseUrl: string, sessionCodes: SkywardSessionCodes): Promise<string> {
  const formData = new URLSearchParams({
    dwd: sessionCodes.dwd,
    wfaacl: sessionCodes.wfaacl,
    encses: sessionCodes.encses,
  });

  const fullUrl = baseUrl + 'sfacademichistory001.w';

  return axios({
    url: fullUrl,
    method: 'post',
    data: formData.toString(),
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
    },
    timeout: 10000,
    maxRedirects: 2,
    validateStatus: (status) => status >= 200 && status < 300,
  }).then(response => {
    const html = response.data;
    if (
      html.includes('Your session has expired') ||
      html.includes('Your session has timed out') ||
      html.includes('WebSpeed error')
    ) {
      const err = new Error('Session expired');
      (err as any).code = 'SESSION_EXPIRED';
      throw err;
    }
    return html;
  });
}

function parseAcademicHistoryHTML(responseData: string): any | null {
  if (!responseData || typeof responseData !== 'string') {
    throw new Error('Invalid response data');
  }

  const root = parse(responseData);
  const title = root.querySelector('title')?.text || '';

  if (title.includes('Family Access') && responseData.length < 5000) {
    throw new Error('Authentication failed - received login page');
  }

  const scripts = root.querySelectorAll('script');

  const pageText = root.querySelector('body')?.text || root.text;
  const hasVerifiedEmptyMarker = /\bno\s+(?:academic\s+history\s+)?records?(?:\s+(?:found|available|to\s+display))?\b/i.test(pageText);
  if (
    !responseData.includes('sf_gridObjects') &&
    /Academic History/i.test(title) &&
    hasVerifiedEmptyMarker
  ) {
    return null;
  }

  for (const script of scripts) {
    const scriptContent = script.innerHTML;

    if (scriptContent && scriptContent.includes('sf_gridObjects')) {
      const sffMatch = /sff\.sv\('sf_gridObjects',\s*\$\.extend\([^,]+,\s*(\{[\s\S]*?\})\)\);/.exec(scriptContent);

      if (sffMatch) {
        try {
          const gridObjectsString = sffMatch[1];
          return parseJavaScriptLiteral(gridObjectsString);
        } catch (e: any) {
          throw new Error(`Failed to parse grid objects: ${e.message}`);
        }
      }
    }
  }

  throw new Error('No academic history data found');
}

function condenseAcademicHistory(gridObjects: any): any {
  if (!gridObjects || typeof gridObjects !== 'object') {
    throw new Error('Skyward academic history data had an invalid format');
  }

  const values = Object.entries(gridObjects);
  const targetPairs = values.filter(([key]) => /gradeGrid_\d+_\d+_\d+/.test(key));

  if (targetPairs.length === 0) {
    throw new Error('Skyward academic history response had no compatible grade grid');
  }

  const targetGrids = targetPairs.map(([, value]) => {
    const grid = value as any;
    if (!grid?.tb || !Array.isArray(grid.tb.r)) {
      throw new Error('Skyward academic history grade grid was incomplete');
    }
    return grid;
  });
  const academicYears: any = {};

  const isValidCourse = (courseData: any) => {
    if (!courseData || !courseData.courseName) return false;

    const name = courseData.courseName.trim();

    const excludePatterns = [
      /^Class$/i, /^Terms$/i, /^\d{4}\s*-\s*\d{4}.*Grade/i,
      /^PR\d+$/i, /^RC\d+$/i, /^EX\d+$/i, /^SM\d+$/i,
      /^\s*$/, /^LUNCH/i,
    ];

    if (excludePatterns.some(pattern => pattern.test(name))) {
      return false;
    }

    return name.length > 2;
  };

  const parseCourseRow = (row: any) => {
    if (!Array.isArray(row?.c) || row.c.length < 18) return null;
    if (row.c.some((cell: any) => typeof cell?.h !== 'string')) return null;

    const columns = row.c.map((cell: any) => {
      const cellRoot = parse(cell.h || '');
      return cellRoot.text.trim();
    });

    const isAltCourse = row.c && row.c.length > 0 && row.c[0].h &&
      typeof row.c[0].h === 'string' &&
      !(row.c[0].h.includes('<a ') || row.c[0].h.includes('<a>'));

    if (!columns[0]) return null;

    return {
      courseName: columns[0] || '',
      terms: columns[1] || '',
      isAltCourse: isAltCourse,
      allColumns: columns,
      grades: {
        pr1: columns[2] || '', pr2: columns[3] || '', rc1: columns[4] || '',
        pr3: columns[5] || '', pr4: columns[6] || '', rc2: columns[7] || '',
        ex1: columns[8] || '', sm1: columns[9] || '', pr5: columns[10] || '',
        pr6: columns[11] || '', rc3: columns[12] || '', pr7: columns[13] || '',
        pr8: columns[14] || '', rc4: columns[15] || '', ex2: columns[16] || '',
        sm2: columns[17] || '',
      },
    };
  };

  const organizeCourseData = (courseData: any) => {
    const { courseName, terms, grades, isAltCourse } = courseData;

    const semester1Grade = grades.sm1 && grades.sm1 !== '' ? grades.sm1 : null;
    const semester2Grade = grades.sm2 && grades.sm2 !== '' ? grades.sm2 : null;
    const finalGrade = semester2Grade || semester1Grade ||
      grades.rc4 || grades.rc3 || grades.rc2 || grades.rc1;

    return {
      courseName, terms, finalGrade, isAltCourse,
      semester1: semester1Grade, semester2: semester2Grade,
      pr1: grades.pr1, pr2: grades.pr2, pr3: grades.pr3, pr4: grades.pr4,
      pr5: grades.pr5, pr6: grades.pr6, pr7: grades.pr7, pr8: grades.pr8,
      rc1: grades.rc1, rc2: grades.rc2, rc3: grades.rc3, rc4: grades.rc4,
      ex1: grades.ex1, ex2: grades.ex2,
    };
  };

  targetGrids.forEach((grid: any) => {
    const rows = grid.tb.r;
    const yearSections: any[] = [];
    let currentSection: any = null;

    rows.forEach((row: any, index: number) => {
      if (!row.c || row.c.length === 0) return;

      const cellRoot = parse(row.c[0].h || '');
      const yearText = cellRoot.text;
      const yearMatch = /(\d{4})\s*-\s*(\d{4}).*Grade\s+(\d+)/.exec(yearText);

      if (yearMatch) {
        const begin = Number(yearMatch[1]);
        const end = Number(yearMatch[2]);
        const grade = Number(yearMatch[3]);
        if (end !== begin + 1 || grade < 1 || grade > 12) {
          throw new Error('Skyward academic history had an invalid year header');
        }
        if (currentSection) {
          yearSections.push(currentSection);
        }
        currentSection = {
          begin: yearMatch[1],
          end: yearMatch[2],
          grade,
          startIndex: index,
          rows: [],
        };
      } else if (currentSection && index > currentSection.startIndex) {
        currentSection.rows.push(row);
      }
    });

    if (currentSection) {
      yearSections.push(currentSection);
    }

    if (rows.length > 0 && yearSections.length === 0) {
      throw new Error('Skyward academic history contained unrecognized populated rows');
    }

    yearSections.forEach(section => {
      const parsedRows = section.rows.map(parseCourseRow);
      const recognizedEmptyRows = section.rows.filter((row: any) => {
        if (!Array.isArray(row?.c)) return false;
        const text = row.c.map((cell: any) => parse(cell?.h || '').text).join(' ');
        return /\bno\s+(?:academic\s+history\s+)?records?\b/i.test(text);
      }).length;
      const structurallyUnknownRows = parsedRows.filter((row: any) => row === null).length
        - recognizedEmptyRows;
      const courses = parsedRows
        .filter((courseData: any) => courseData && isValidCourse(courseData))
        .map(organizeCourseData);

      if (section.rows.length > 0 && courses.length === 0 && structurallyUnknownRows > 0) {
        throw new Error('Skyward academic history contained malformed populated rows');
      }

      // Skyward can include legitimate pre-high-school credit sections. Parse
      // and validate them, but keep the product's unified transcript at 9-12.
      if (section.grade < 9) return;

      const regularCourses = courses.filter((course: any) => !course.isAltCourse);
      const altCourses = courses.filter((course: any) => course.isAltCourse);

      const academicYearKey = `${section.begin}-${section.end}`;

      if (regularCourses.length > 0 || section.rows.length > 1) {
        const regularCoursesObject: any = {};
        const courseNameCounts: any = {};

        regularCourses.forEach((course: any) => {
          let courseKey = course.courseName;

          if (regularCoursesObject[courseKey]) {
            courseNameCounts[course.courseName] = (courseNameCounts[course.courseName] || 1) + 1;
            courseKey = `${course.courseName}_${courseNameCounts[course.courseName]}`;
          } else if (courseNameCounts[course.courseName]) {
            courseNameCounts[course.courseName] += 1;
            courseKey = `${course.courseName}_${courseNameCounts[course.courseName]}`;
          } else {
            courseNameCounts[course.courseName] = 1;
          }

          regularCoursesObject[courseKey] = {
            terms: course.terms,
            finalGrade: course.finalGrade,
            sm1: course.semester1, sm2: course.semester2,
            pr1: course.pr1, pr2: course.pr2, pr3: course.pr3, pr4: course.pr4,
            pr5: course.pr5, pr6: course.pr6, pr7: course.pr7, pr8: course.pr8,
            rc1: course.rc1, rc2: course.rc2, rc3: course.rc3, rc4: course.rc4,
            ex1: course.ex1, ex2: course.ex2,
          };
        });

        academicYears[academicYearKey] = {
          grade: section.grade,
          courses: regularCoursesObject,
        };
      }

      if (altCourses.length > 0) {
        if (!academicYears.alt) {
          academicYears.alt = {};
        }

        const altCoursesObject: any = {};
        const altCourseNameCounts: any = {};

        altCourses.forEach((course: any) => {
          let courseKey = course.courseName;

          if (altCoursesObject[courseKey]) {
            altCourseNameCounts[course.courseName] = (altCourseNameCounts[course.courseName] || 1) + 1;
            courseKey = `${course.courseName}_${altCourseNameCounts[course.courseName]}`;
          } else if (altCourseNameCounts[course.courseName]) {
            altCourseNameCounts[course.courseName] += 1;
            courseKey = `${course.courseName}_${altCourseNameCounts[course.courseName]}`;
          } else {
            altCourseNameCounts[course.courseName] = 1;
          }

          altCoursesObject[courseKey] = {
            terms: course.terms,
            finalGrade: course.finalGrade,
            sm1: course.semester1, sm2: course.semester2,
            pr1: course.pr1, pr2: course.pr2, pr3: course.pr3, pr4: course.pr4,
            pr5: course.pr5, pr6: course.pr6, pr7: course.pr7, pr8: course.pr8,
            rc1: course.rc1, rc2: course.rc2, rc3: course.rc3, rc4: course.rc4,
            ex1: course.ex1, ex2: course.ex2,
          };
        });

        academicYears.alt[academicYearKey] = {
          grade: section.grade,
          courses: altCoursesObject,
        };
      }
    });
  });

  return academicYears;
}
