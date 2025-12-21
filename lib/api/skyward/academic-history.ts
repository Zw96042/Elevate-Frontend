// Skyward academic history API
import axios from 'axios';
import { parse } from 'node-html-parser';
import { SkywardSessionCodes } from '../../types/api';
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
    const result = condenseAcademicHistory(gridObjects);
    
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
      validateStatus: (status) => status < 500,
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
    return { data: [], raw: htmlData };
  }

  const results = /\$\.extend\(\(sff\.getValue\('sf_gridObjects'\) \|\| {}\), ([\s\S]*)\)\);/g.exec(scriptContent);

  if (!results) {
    return { data: [], raw: htmlData };
  }

  const parsedData = new Function(`return ${results[1]}`)();
  const values = Object.entries(parsedData);
  const targetPair = values.find(([key]) => /stuGradesGrid_\d+_\d+/.test(key));

  if (!targetPair) {
    return { data: [], raw: htmlData };
  }

  const gridData = targetPair[1] as any;
  if (!gridData.tb || !gridData.tb.r) {
    return { data: [], raw: htmlData };
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
  const courses = gridData.tb.r
    .filter((row: any) => row.c && row.c.length > 0 && row.c[0].cId)
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
            const score = Number(scoreText);

            if (course && !gbID) {
              const gId = element.getAttribute('data-gid');
              if (gId) {
                gbID = gId;
              }
            }

            if (course && bucket) {
              courseNumber = course;
              if (!isNaN(score)) {
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

      return null;
    })
    .filter((course: any) => course !== null);

  return { data: courses, raw: htmlData };
}

/**
 * Combine academic history with current gradebook data
 */
export function combineAcademicData(academicHistory: any, gradebookData: any): any {
  if (!gradebookData || !gradebookData.data || gradebookData.data.length === 0) {
    return academicHistory;
  }

  const yearKeys = Object.keys(academicHistory).filter(k => k !== 'alt');
  if (yearKeys.length === 0) {
    return academicHistory;
  }

  const latestYear = yearKeys.sort().reverse()[0];
  const yearData = academicHistory[latestYear];
  if (!yearData || !yearData.courses) {
    return academicHistory;
  }

  const academicCourses = yearData.courses;
  const bucketMap: any = {
    'TERM 1': 'pr1', 'TERM 2': 'pr2', 'TERM 3': 'rc1',
    'TERM 4': 'pr3', 'TERM 5': 'pr4', 'TERM 6': 'rc2',
    'TERM 7': 'pr5', 'TERM 8': 'pr6', 'TERM 9': 'rc3',
    'TERM 10': 'pr7', 'TERM 11': 'pr8', 'TERM 12': 'rc4',
    'SEM 1': 'sm1', 'SEM 2': 'sm2',
  };

  const newCourses: any = {};

  for (const gradebookCourse of gradebookData.data) {
    const lookupKey = gradebookCourse.courseName.trim().toUpperCase();
    const academicKey = Object.keys(academicCourses).find(k => k.trim().toUpperCase() === lookupKey);
    const baseCourse = academicKey ? academicCourses[academicKey] : null;

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

    newCourses[gradebookCourse.courseName] = courseObj;
  }

  academicHistory[latestYear].courses = newCourses;
  return academicHistory;
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
  
  // Parallel requests with stagger
  const academicHistoryPromise = fetchAcademicHistory(baseUrl, sessionCodes);

  const gradebookPromise = new Promise<string>((resolve, reject) => {
    setTimeout(async () => {
      try {
        const result = await fetchGradebookHTML(baseUrl, sessionCodes);
        resolve(result);
      } catch (error) {
        reject(error);
      }
    }, 50);
  });

  const timeoutPromise = new Promise<never>((_, reject) => {
    setTimeout(() => reject(new Error('PARALLEL_TIMEOUT')), 8000);
  });

  try {
    const [academicHistory, gradebookHtml] = await Promise.race([
      Promise.all([academicHistoryPromise, gradebookPromise]),
      timeoutPromise,
    ]);


    const gradebookData = await parseGradebookHTML(gradebookHtml);
    // console.log("BBB", gradebookData);
    const result = combineAcademicData(academicHistory, gradebookData);
    // console.log("BBB", result, "BBB");
    
    const duration = Date.now() - startTime;
    logger.success(Modules.API_HISTORY, `Combined academic data loaded (${duration}ms)`);
    
    return result;
  } catch (error: any) {
    if (error.message === 'PARALLEL_TIMEOUT') {
      logger.warn(Modules.API_HISTORY, 'Parallel fetch timed out, falling back to sequential');
      
      // Fallback to sequential
      const academicHistory = await fetchAcademicHistory(baseUrl, sessionCodes);
      const gradebookHtml = await fetchGradebookHTML(baseUrl, sessionCodes);
      const gradebookData = await parseGradebookHTML(gradebookHtml);
      const result = combineAcademicData(academicHistory, gradebookData);
      
      const duration = Date.now() - startTime;
      logger.success(Modules.API_HISTORY, `Combined academic data loaded sequentially (${duration}ms)`);
      
      return result;
    }
    
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
    validateStatus: (status) => status < 500,
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

function parseAcademicHistoryHTML(responseData: string): any {
  if (!responseData || typeof responseData !== 'string') {
    throw new Error('Invalid response data');
  }

  const root = parse(responseData);
  const title = root.querySelector('title')?.text || '';

  if (title.includes('Family Access') && responseData.length < 5000) {
    throw new Error('Authentication failed - received login page');
  }

  const scripts = root.querySelectorAll('script');

  for (const script of scripts) {
    const scriptContent = script.innerHTML;

    if (scriptContent && scriptContent.includes('sf_gridObjects')) {
      const sffMatch = /sff\.sv\('sf_gridObjects',\s*\$\.extend\([^,]+,\s*(\{[\s\S]*?\})\)\);/.exec(scriptContent);

      if (sffMatch) {
        try {
          const gridObjectsString = sffMatch[1];
          return new Function(`return ${gridObjectsString}`)();
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
    return {};
  }

  const values = Object.entries(gridObjects);
  const targetPairs = values.filter(([key]) => /gradeGrid_\d+_\d+_\d+/.test(key));

  if (targetPairs.length === 0) {
    return {};
  }

  const targetGrids = targetPairs.map(([, value]) => value);
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
    if (!row.c || row.c.length === 0) return null;

    const columns = row.c.map((cell: any) => {
      const cellRoot = parse(cell.h || '');
      return cellRoot.text.trim();
    });

    const isAltCourse = row.c && row.c.length > 0 && row.c[0].h &&
      typeof row.c[0].h === 'string' &&
      !(row.c[0].h.includes('<a ') || row.c[0].h.includes('<a>'));

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

    console.log("Course:", courseName, "Final Grade Ex1:", grades.ex1);
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
        if (currentSection) {
          yearSections.push(currentSection);
        }
        currentSection = {
          begin: yearMatch[1],
          end: yearMatch[2],
          grade: parseInt(yearMatch[3], 10),
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

    yearSections.forEach(section => {
      const courses = section.rows
        .map(parseCourseRow)
        .filter((courseData: any) => courseData && isValidCourse(courseData))
        .map(organizeCourseData);

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
