// lib/skywardAcademicClient.tsx
// This file contains the academic history and grades scraping logic migrated from the backend.
// It directly calls Skyward endpoints and combines academic history with current grades.

import axios from 'axios';
import { parse } from 'node-html-parser';

export interface SkywardSessionCodes {
  dwd: string;
  wfaacl: string;
  encses: string;
  'User-Type': string;
  sessionid: string;
}

// ===== ACADEMIC HISTORY SCRAPING =====
const scrapeHistoryData = async (baseUrl: string, sessionCodes: SkywardSessionCodes) => {
    const startTime = Date.now();
    console.log('=== scrapeHistoryData: Starting ===');
    console.log('📍 scrapeHistoryData: Base URL:', baseUrl);
    console.log('🔑 scrapeHistoryData: Session codes keys:', Object.keys(sessionCodes));
    
    if (!sessionCodes.dwd || !sessionCodes.wfaacl || !sessionCodes.encses) {
      throw new Error('dwd, wfaacl, & encses are required');
    }
    
    // Use URLSearchParams like auth client does
    const formDataStartTime = Date.now();
    const formData = new URLSearchParams({
      dwd: sessionCodes.dwd,
      wfaacl: sessionCodes.wfaacl,
      encses: sessionCodes.encses,
    });
    const body = formData.toString();
    const formDataTime = Date.now() - formDataStartTime;
    console.log(`📦 scrapeHistoryData: Request body prepared (${formDataTime}ms), preview:`, body.substring(0, 100) + '...');
    
    // Use same URL construction as backend - no slash between baseUrl and endpoint
    const fullUrl = baseUrl + 'sfacademichistory001.w';
    console.log('🌐 scrapeHistoryData: Full URL being constructed:', fullUrl);
    
    const requestStartTime = Date.now();
    const response = await axios({
      url: fullUrl,
      method: 'post',
      data: body,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    });
    const requestTime = Date.now() - requestStartTime;
    const totalTime = Date.now() - startTime;
    
    console.log(`📡 scrapeHistoryData: Response received (${requestTime}ms), total: ${totalTime}ms, status: ${response.status}, data length: ${response.data?.length}`);
    console.log('Response data preview:', response.data?.substring(0, 200));  try {
    const response = await axios({
      url: fullUrl,
      method: 'post',
      data: body,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    });
    
    console.log('📖 Academic history response status:', response.status);
    console.log('📖 Academic history response length:', response.data?.length || 0);
    console.log('📖 Response headers:', response.headers);
    
    // Log first 500 characters of response to debug
    if (response.data && response.data.length < 1000) {
      console.log('📖 Full response (short):', response.data);
    } else {
      console.log('📖 Response preview:', response.data?.substring(0, 500) + '...');
    }
    
    // Check for session expiration like backend does
    const html = response.data;
    if (html.includes('Your session has expired') || 
        html.includes('Your session has timed out') || 
        html.includes('WebSpeed error from WebSpeed ISAPI Messenger(WSISA)') || 
        html.includes('WebSpeed Agent Error: Agent did not return an HTML page')) {
      const err = new Error('Session expired');
      (err as any).code = 'SESSION_EXPIRED';
      throw err;
    }
    
    return response;
  } catch (error: any) {
    console.error('❌ Error scraping academic history:', error.message);
    console.error('❌ Error details:', error.response?.data || error.response?.status);
    throw error;
  }
};

const parseHistoryResponse = (responseData: string) => {
  console.log('🔍 Parsing academic history response, length:', responseData?.length || 0);
  
  if (!responseData || typeof responseData !== 'string') {
    throw new Error('Invalid response data');
  }
  
  const root = parse(responseData);
  
  // Check if we got a login page instead of data
  const title = root.querySelector('title')?.text || '';
  console.log('🔍 Page title:', title);
  
  if (title.includes('Family Access') && responseData.length < 5000) {
    throw new Error('Authentication failed - received login page instead of data. Please check your auth tokens or get fresh ones.');
  }
  
  // Look for JavaScript variables in script tags
  const scripts = root.querySelectorAll('script');
  console.log('🔍 Found scripts:', scripts.length);
  
  for (const script of scripts) {
    const scriptContent = script.innerHTML;
    
    if (scriptContent && scriptContent.includes('sf_gridObjects')) {
      console.log('🔍 Found sf_gridObjects script');
      // Extract the sff.sv call with sf_gridObjects
      const sffMatch = /sff\.sv\('sf_gridObjects',\s*\$\.extend\([^,]+,\s*(\{[\s\S]*?\})\)\);/.exec(scriptContent);
      
      if (sffMatch) {
        console.log('🔍 Found sf_gridObjects match');
        try {
          const gridObjectsString = sffMatch[1];
          // Use Function constructor instead of eval for safety
          const gridData = new Function(`return ${gridObjectsString}`)();
          console.log('✅ Successfully parsed grid objects, keys:', Object.keys(gridData || {}));
          return gridData;
        } catch (e: any) {
          console.log('❌ Failed to parse grid objects:', e.message);
        }
      } else {
        console.log('🔍 sf_gridObjects found but no match for sff.sv pattern');
      }
    }
  }
  
  console.log('❌ No sf_gridObjects found in any script tags');
  throw new Error('No academic history data found. This could be due to: 1) Invalid/expired authentication tokens, 2) No access permissions, or 3) No history data available.');
};

// ===== CONDENSING LOGIC =====
const condenseHistoryData = (gridObjects: any) => {
  console.log('🔄 Condensing history data...');
  
  if (!gridObjects || typeof gridObjects !== 'object') {
    console.log('❌ Invalid grid objects');
    return {};
  }
  
  const values = Object.entries(gridObjects);
  const targetPairs = values.filter(([key]) => /gradeGrid_\d+_\d+_\d+/.test(key));
  
  console.log('🔄 Found target grade grids:', targetPairs.length);
  
  if (targetPairs.length === 0) {
    console.log('❌ No grade grids found');
    return {};
  }
  
  const targetGrids = targetPairs.map(([, value]) => value);
  const academicYears: any = {};
  
  const isValidCourse = (courseData: any) => {
    if (!courseData || !courseData.courseName) return false;
    
    const name = courseData.courseName.trim();
    
    // Filter out obvious non-courses
    const excludePatterns = [
      /^Class$/i, /^Terms$/i, /^\d{4}\s*-\s*\d{4}.*Grade/i,
      /^PR\d+$/i, /^RC\d+$/i, /^EX\d+$/i, /^SM\d+$/i,
      /^\s*$/, /^LUNCH/i,
    ];
    
    if (excludePatterns.some(pattern => pattern.test(name))) {
      return false;
    }

    // Include course if it has a valid name (even without grades)
    return name.length > 2; // Must have more than 2 characters to be a valid course name
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
      }
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
  
  targetGrids.forEach((grid: any, gridIndex: number) => {
    console.log(`🔄 Processing grid ${gridIndex + 1}/${targetGrids.length}`);
    
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
          rows: []
        };
        console.log(`🔄 Found academic year: ${yearMatch[1]}-${yearMatch[2]} Grade ${yearMatch[3]}`);
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
      
      console.log(`🔄 Academic year ${academicYearKey}: ${regularCourses.length} regular courses, ${altCourses.length} alt courses`);
      
      // Include academic year even if no valid courses (for courses without grades)
      if (regularCourses.length > 0 || section.rows.length > 1) { // Include if has courses or more than just header
        const regularCoursesObject: any = {};
        const courseNameCounts: any = {};
        
        regularCourses.forEach((course: any) => {
          let courseKey = course.courseName;
          
          // Handle duplicate course names by adding a suffix
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
          courses: regularCoursesObject
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
          
          // Handle duplicate course names by adding a suffix
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
          courses: altCoursesObject
        };
      }
    });
  });
  
  console.log('✅ Condensed academic years:', Object.keys(academicYears));
  return academicYears;
};

// ===== ACADEMIC HISTORY MAIN FUNCTION =====
const getAcademicHistory = async (baseUrl: string, sessionCodes: SkywardSessionCodes) => {
  const startTime = Date.now();
  console.log('📚 getAcademicHistory: Getting academic history...');
  
  try {
    const scrapeStartTime = Date.now();
    const response = await scrapeHistoryData(baseUrl, sessionCodes);
    const scrapeTime = Date.now() - scrapeStartTime;
    
    const parseStartTime = Date.now();
    const gridObjects = parseHistoryResponse(response.data);
    const parseTime = Date.now() - parseStartTime;
    
    const condenseStartTime = Date.now();
    const condensedData = condenseHistoryData(gridObjects);
    const condenseTime = Date.now() - condenseStartTime;
    
    const totalTime = Date.now() - startTime;
    console.log(`✅ getAcademicHistory: Success! Total: ${totalTime}ms (scrape: ${scrapeTime}ms, parse: ${parseTime}ms, condense: ${condenseTime}ms)`);
    return condensedData;
  } catch (error: any) {
    const totalTime = Date.now() - startTime;
    console.error(`❌ getAcademicHistory: Failed after ${totalTime}ms:`, error.message);
    throw new Error(`Failed to get academic history: ${error.message}`);
  }
};

// ===== GRADEBOOK SCRAPING =====
const scrapeGradebook = async (baseUrl: string, sessionCodes: SkywardSessionCodes) => {
  const startTime = Date.now();
  console.log('📊 scrapeGradebook: Scraping gradebook from:', baseUrl);
  
  const postData = new URLSearchParams({ ...sessionCodes });
  const gradebookUrl = baseUrl + 'sfgradebook001.w';
  
  try {
    const requestStartTime = Date.now();
    const gradebookResponse = await axios.post(gradebookUrl, postData.toString(), {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    });
    const requestTime = Date.now() - requestStartTime;
    
    const htmlData = gradebookResponse.data;
    const totalTime = Date.now() - startTime;
    console.log(`📊 scrapeGradebook: Response received (${requestTime}ms), total: ${totalTime}ms, status: ${gradebookResponse.status}, length: ${htmlData?.length || 0}`);

    if (htmlData.includes('Your session has expired') || htmlData.includes('Your session has timed out')) {
      const err = new Error('Session expired');
      (err as any).code = 'SESSION_EXPIRED';
      throw err;
    }

    return htmlData;
  } catch (error: any) {
    console.error('❌ Error scraping gradebook:', error.message);
    throw error;
  }
};

// ===== GRADEBOOK PARSING =====
const parseGradebookData = (htmlData: string) => {
  console.log('📊 Parsing gradebook data, length:', htmlData?.length || 0);
  
  const root = parse(htmlData);
  
  // Find script with grade data
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
    console.log('❌ No grade data script found');
    return { data: [], raw: htmlData };
  }
  
  try {
    // Extract grid objects 
    const results = /\$\.extend\(\(sff\.getValue\('sf_gridObjects'\) \|\| {}\), ([\s\S]*)\)\);/g.exec(scriptContent);
    
    if (!results) {
      console.log('❌ Could not parse grade data from script');
      return { data: [], raw: htmlData };
    }

    const parsedData = new Function(`return ${results[1]}`)();
    
    // Find the grades grid
    const values = Object.entries(parsedData);
    const targetPair = values.find(([key]) => /stuGradesGrid_\d+_\d+/.test(key));
    
    if (!targetPair) {
      console.log('❌ No grades grid found');
      return { data: [], raw: htmlData };
    }

    const gridData = targetPair[1] as any;
    if (!gridData.tb || !gridData.tb.r) {
      console.log('❌ No grid data or rows found');
      return { data: [], raw: htmlData };
    }

    console.log('📊 Processing grades grid with', gridData.tb.r.length, 'rows');
    
    // Extract course details from HTML
    const courseDetails: any = {};
    
    root.querySelectorAll('table[id*="classDesc_"]').forEach(table => {
      const tableId = table.getAttribute('id') || '';
      // classDesc_stuId_corNumId_0_section
      const idMatch = /classDesc_(\d+)_(\d+)_0_(\d+)/.exec(tableId);
      
      if (idMatch) {
        const stuId = idMatch[1];
        const corNumId = Number(idMatch[2]);
        const section = idMatch[3];
        
        // Extract course name
        const courseName = table.querySelector('span.bld.classDesc a')?.text?.trim() || '';
        
        // Extract instructor name  
        const instructorElement = table.querySelector('tr:last-child td a');
        const instructorName = instructorElement?.text?.trim() || '';
        
        // Extract period info
        const periodRow = table.querySelector('tr:nth-child(2) td');
        const periodText = periodRow?.text || '';
        const periodMatch = /Period\s*(\d+)/.exec(periodText);
        const period = periodMatch ? Number(periodMatch[1]) : null;
        
        // Extract time info
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
          section
        };
        
        console.log('📊 Extracted course IDs:', {
          courseName,
          corNumId,
          tableId,
          stuId,
          section
        });
      }
    });
    
    console.log('📊 Found course details for', Object.keys(courseDetails).length, 'courses');
    console.log('📊 Course details object:', courseDetails);
    
    // Process grade data and extract gbID for each course
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
              
              // Extract gbID from the first grade element we find
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
          
          const courseObj = {
            course: courseNumber,
            courseName: details.courseName || 'Unknown Course',
            instructor: details.instructor || 'Unknown Instructor', 
            period: details.period || 0,
            time: details.time || null,
            semester: 'both' as const, // We'll determine this later
            scores: courseData,
            // Add the essential IDs needed for assignment fetching
            stuId: details.stuId,
            corNumId: details.corNumId,
            section: details.section,
            gbId: gbID
          };
          
          console.log('📊 Course parsed with IDs:', {
            courseName: courseObj.courseName,
            courseNumber: courseNumber,
            stuId: courseObj.stuId,
            corNumId: courseObj.corNumId,
            section: courseObj.section,
            gbId: courseObj.gbId,
            hasDetails: !!details,
            detailsKeys: Object.keys(details)
          });
          
          return courseObj;
        }
        
        return null;
      })
      .filter((course: any) => course !== null);
    
    console.log('📊 Parsed', courses.length, 'courses with grades');
    return { data: courses, raw: htmlData };
    
  } catch (error: any) {
    console.error('❌ Error parsing gradebook data:', error.message);
    return { data: [], raw: htmlData };
  }
};

// ===== COMBINATION LOGIC =====
const combineAcademicHistoryWithGradebook = (academicHistory: any, gradebookData: any) => {
  console.log('🔗 Combining academic history with current gradebook data...');
  
  if (!gradebookData || !gradebookData.data || gradebookData.data.length === 0) {
    console.log('📊 No gradebook data to combine, returning history only');
    return academicHistory;
  }
  
  // Find the latest academic year (exclude 'alt')
  const yearKeys = Object.keys(academicHistory).filter(k => k !== 'alt');
  if (yearKeys.length === 0) {
    console.log('📊 No academic years found, returning history only');
    return academicHistory;
  }
  
  const latestYear = yearKeys.sort().reverse()[0];
  const yearData = academicHistory[latestYear];
  if (!yearData || !yearData.courses) {
    console.log('📊 No courses in latest year, returning history only');
    return academicHistory;
  }

  console.log('📊 Combining with latest year:', latestYear);
  
  // Map scrape report courseName to academic history courseKey
  const academicCourses = yearData.courses;
  const bucketMap: any = {
    'TERM 1': 'pr1', 'TERM 2': 'pr2', 'TERM 3': 'rc1',
    'TERM 4': 'pr3', 'TERM 5': 'pr4', 'TERM 6': 'rc2',
    'TERM 7': 'pr5', 'TERM 8': 'pr6', 'TERM 9': 'rc3',
    'TERM 10': 'pr7', 'TERM 11': 'pr8', 'TERM 12': 'rc4',
    'SEM 1': 'sm1', 'SEM 2': 'sm2'
  };

  // Build new courses object only with classes from gradebook
  const newCourses: any = {};
  
  for (const gradebookCourse of gradebookData.data) {
    const lookupKey = gradebookCourse.courseName.trim().toUpperCase();
    // Find matching academic history course (case-insensitive)
    const academicKey = Object.keys(academicCourses).find(k => k.trim().toUpperCase() === lookupKey);
    const baseCourse = academicKey ? academicCourses[academicKey] : null;

    // Start with academic history data if available, else blank
    const courseObj = baseCourse ? { ...baseCourse } : {
      terms: gradebookCourse.semester === 'both' ? '1 - 4' : '',
      finalGrade: '',
      sm1: null, sm2: null,
      pr1: '', pr2: '', pr3: '', pr4: '', pr5: '', pr6: '', pr7: '', pr8: '',
      rc1: '', rc2: '', rc3: '', rc4: '', ex1: '', ex2: ''
    };

    // Add courseId, instructor, period from gradebook
    courseObj.courseId = gradebookCourse.course;
    courseObj.instructor = gradebookCourse.instructor;
    courseObj.period = gradebookCourse.period;
    if (gradebookCourse.time) courseObj.time = gradebookCourse.time;
    
    // Add essential IDs needed for assignment fetching
    courseObj.stuId = gradebookCourse.stuId;
    courseObj.corNumId = gradebookCourse.corNumId;
    courseObj.section = gradebookCourse.section;
    courseObj.gbId = gradebookCourse.gbId;

    // Map current scores into buckets  
    if (Array.isArray(gradebookCourse.scores)) {
      for (const scoreObj of gradebookCourse.scores) {
        const bucket = scoreObj.bucket;
        const field = bucketMap[bucket];
        if (field && field !== 'ex1' && field !== 'ex2') {
          courseObj[field] = scoreObj.score;
        }
      }
    }

    // Always preserve ex1 and ex2 from academic history if present
    if (baseCourse) {
      courseObj.ex1 = baseCourse.ex1;
      courseObj.ex2 = baseCourse.ex2;
    }

    newCourses[gradebookCourse.courseName] = courseObj;
  }

  // Replace courses for latest year with newCourses
  academicHistory[latestYear].courses = newCourses;
  
  console.log('🔗 Combined', Object.keys(newCourses).length, 'courses for', latestYear);
  return academicHistory;
};

// ===== SIMPLE PARSING FOR DEBUGGING =====
const parseReportDataSimple = async (htmlData: string) => {
  console.log('🔍 Parsing gradebook data (simple)...');
  
  try {
    const root = parse(htmlData);
    
    // Look for script with data-rel="sff"
    const scripts = root.querySelectorAll('script[data-rel="sff"]');
    console.log('🔍 Found sff scripts:', scripts.length);
    
    if (scripts.length === 0) {
      console.log('❌ No script with data-rel="sff" found');
      return { data: [], raw: htmlData };
    }

    const script = scripts[0].innerHTML;
    console.log('🔍 Script content length:', script?.length || 0);
    
    // Look for the grid objects pattern
    const results = /\$\.extend\(\(sff\.getValue\('sf_gridObjects'\) \|\| {}\), ([\s\S]*)\)\);/g.exec(script);
    
    if (!results) {
      console.log('❌ Could not find sf_gridObjects pattern in script');
      return { data: [], raw: htmlData };
    }

    console.log('✅ Found sf_gridObjects pattern');
    const parsedData = new Function(`return ${results[1]}`)();
    
    // Find the grades grid
    const values = Object.entries(parsedData);
    console.log('🔍 Grid object keys:', values.map(([key]) => key));
    
    const targetPair = values.find(([key]) => /stuGradesGrid_\d+_\d+/.test(key));
    
    if (!targetPair) {
      console.log('❌ No grades grid found');
      return { data: [], raw: htmlData };
    }

    console.log('✅ Found grades grid:', targetPair[0]);
    const gridData = targetPair[1] as any;
    
    if (!gridData.tb || !gridData.tb.r) {
      console.log('❌ Grid data has no table/rows');
      return { data: [], raw: htmlData };
    }

    console.log('✅ Grid has', gridData.tb.r.length, 'rows');
    
    // For now, just return basic structure to test if parsing works
    const simpleCourses = [{
      course: 1,
      courseName: 'Test Course',
      instructor: 'Test Instructor',
      period: 1,
      time: null,
      semester: 'both' as const,
      scores: []
    }];
    
    return { data: simpleCourses, raw: htmlData };
  } catch (error: any) {
    console.error('❌ Error parsing gradebook data:', error.message);
    return { data: [], raw: htmlData };
  }
};

// ===== MAIN COMBINED FUNCTION =====
export const getCombinedAcademicHistoryReport = async (baseUrl: string, sessionCodes: SkywardSessionCodes) => {
  const totalStartTime = Date.now();
  console.log('🚀 getCombinedAcademicHistoryReport: Starting PARALLEL combined academic history report...');
  
  try {
    // Execute both API calls in parallel for maximum speed
    console.log('⚡ getCombinedAcademicHistoryReport: Launching parallel requests...');
    const parallelStartTime = Date.now();
    
    const [academicHistory, gradebookHtml] = await Promise.all([
      getAcademicHistory(baseUrl, sessionCodes),
      scrapeGradebook(baseUrl, sessionCodes)
    ]);
    
    const parallelTime = Date.now() - parallelStartTime;
    console.log(`⚡ getCombinedAcademicHistoryReport: Parallel requests completed (${parallelTime}ms)`);
    
    // Parse gradebook data (academic history is already parsed)
    const parseStartTime = Date.now();
    const gradebookData = parseGradebookData(gradebookHtml);
    const parseTime = Date.now() - parseStartTime;
    
    // Combine the data
    console.log(`🔗 getCombinedAcademicHistoryReport: Combining data (parse: ${parseTime}ms)...`);
    const combineStartTime = Date.now();
    const combinedData = combineAcademicHistoryWithGradebook(academicHistory, gradebookData);
    const combineTime = Date.now() - combineStartTime;
    
    const totalTime = Date.now() - totalStartTime;
    console.log(`✅ getCombinedAcademicHistoryReport: PARALLEL SUCCESS! Total: ${totalTime}ms (parallel: ${parallelTime}ms, parse: ${parseTime}ms, combine: ${combineTime}ms)`);
    return combinedData;
    
  } catch (error: any) {
    const totalTime = Date.now() - totalStartTime;
    console.error(`❌ getCombinedAcademicHistoryReport: PARALLEL FAILED after ${totalTime}ms:`, error.message);
    throw error;
  }
};
