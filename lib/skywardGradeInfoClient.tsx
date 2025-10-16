import axios from 'axios';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { parse } from 'node-html-parser';

// ===== TYPE DEFINITIONS =====
export interface GradeInfoParams {
  stuId: string;
  corNumId: string;
  gbId: string;
  section: string;
  bucket: string;
  entityId?: string;
  track?: string;
  subjectId?: string;
  dialogLevel?: string;
  isEoc?: string;
  customUrl?: string;
}

interface Assignment {
  date: string;
  name: string;
  grade: number | null;
  score: number | null;
  points: { earned: number; total: number } | null;
  meta: { type: string; note: string }[];
}

interface GradeCategory {
  category: string;
  weight: number | null;
  adjustedWeight: number | null;
  assignments: Assignment[];
}

interface GradeInfoResult {
  course: string;
  instructor: string;
  period: number | null;
  lit: {
    name: string;
    begin: string | null;
    end: string | null;
  };
  gradebook: GradeCategory[];
  score: number | null;
  grade: number | null;
}

// ===== HELPER FUNCTIONS =====
const extractCourseExtraInfo = (html: string) => {
  const root = parse(html);
  
  // Find course link
  const courseLink = root.querySelector("h2.gb_heading a");
  if (!courseLink) return null;
  
  const href = courseLink.getAttribute('href');
  if (!href) return null;
  
  // Extract parameters from the href
  const url = new URL(href, 'http://dummy.com'); // Use dummy base for relative URLs
  const params = new URLSearchParams(url.search);
  
  return {
    corNumId: params.get('corNumId') || '',
    gbId: params.get('gbId') || '',
    section: params.get('section') || '',
    entityId: params.get('entityId') || '',
    bucket: params.get('bucket') || '',
    track: params.get('track') || '',
    subjectId: params.get('subjectId') || '',
    dialogLevel: params.get('dialogLevel') || '',
    isEoc: params.get('isEoc') || 'no',
  };
};

const getSessionCodes = async () => {
  const dwd = await AsyncStorage.getItem('dwd') || '';
  const wfaacl = await AsyncStorage.getItem('wfaacl') || '';
  const encses = await AsyncStorage.getItem('encses') || '';
  const sessionid = await AsyncStorage.getItem('sessionid') || '';
  const userType = await AsyncStorage.getItem('User-Type') || '';

  return {
    dwd,
    wfaacl,
    encses,
    sessionid,
    'User-Type': userType,
  };
};

// ===== HTTP REQUEST =====
const fetchGradeInfoHTML = async (params: GradeInfoParams, url: string): Promise<string> => {
  try {
    const sessionCodes = await getSessionCodes();
    
    console.log('📋 Fetching grade info from:', url);
    console.log('📋 Grade info params:', {
      stuId: params.stuId,
      corNumId: params.corNumId,
      gbId: params.gbId,
      section: params.section,
      bucket: params.bucket
    });

    const fullUrl = `${url}httploader.p?file=sfgradebook001.w`;
    console.log('TEST URL: ', fullUrl);

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

    console.log('📋 POST data keys:', Object.keys(postData));

    // Create form data string
    const formDataString = Object.entries(postData)
      .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
      .join('&');

    console.log('📋 Form data length:', formDataString.length);

    const response = await axios.post(fullUrl, formDataString, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
      },
      timeout: 30000,
    });

    const rawResponse = response.data;
    console.log('📋 Raw response received, length:', rawResponse?.length || 0);
    console.log('📋 Response status:', response.status);
    
    if (!rawResponse || typeof rawResponse !== 'string') {
      throw new Error('Invalid response received');
    }

    // Extract HTML from CDATA section (EXACTLY like backend)
    console.log('📋 Extracting HTML from CDATA section...');
    const match = rawResponse.match(/<output><!\[CDATA\[(.*)\]\]><\/output>/s);
    const html = match && match[1] ? match[1] : rawResponse;
    
    console.log('📋 Extracted HTML length:', html?.length || 0);
    console.log('📋 CDATA extraction:', match ? 'SUCCESS' : 'FALLBACK TO RAW');

    if (html.length < 1000) {
      console.log('📋 Short HTML content:', html.substring(0, 500));
    }

    return html;
  } catch (error: any) {
    console.error('❌ Error fetching grade info HTML:', error.message);
    throw error;
  }
};

// ===== HTML PARSING (EXACTLY matching backend implementation) =====
const parseGradeInfo = (html: string): GradeInfoResult => {
  console.log('📋 Parsing grade info HTML, length:', html?.length || 0);
  
  // Check for empty <data> in XML response (session expired) - EXACT backend match
  if (typeof html === 'string' && html.match(/<data><!\[CDATA\[\s*\]\]><\/data>/)) {
    const err = new Error('Session expired');
    (err as any).code = 'SESSION_EXPIRED';
    throw err;
  }

  const root = parse(html);
  
  // COMPREHENSIVE HTML STRUCTURE DEBUGGING
  console.log('📋 === HTML STRUCTURE ANALYSIS ===');
  
  // Check all tables in the document
  const allTables = root.querySelectorAll("table");
  console.log('📋 Total tables found:', allTables.length);
  
  allTables.forEach((table, index) => {
    const id = table.getAttribute('id') || 'no-id';
    const className = table.getAttribute('class') || 'no-class';
    const rowCount = table.querySelectorAll('tr').length;
    console.log(`📋 Table ${index}: id="${id}" class="${className}" rows=${rowCount}`);
  });
  
  // Check for different possible table selectors
  const possibleSelectors = [
    "table[id^='grid_stuTermSummaryGrid']",
    "table[id^='grid_stuAssignmentSummaryGrid']", 
    "table[id*='Term']",
    "table[id*='Assignment']",
    "table[id*='Summary']",
    "table[id*='Grid']",
    "table[id*='stu']"
  ];
  
  possibleSelectors.forEach(selector => {
    const found = root.querySelectorAll(selector);
    if (found.length > 0) {
      console.log(`📋 Found ${found.length} tables with selector: ${selector}`);
      found.forEach((table, i) => {
        console.log(`📋   - Table ${i}: id="${table.getAttribute('id')}" rows=${table.querySelectorAll('tr').length}`);
      });
    }
  });
  
  // Check for any elements with 'grid' in the id
  const gridElements = root.querySelectorAll("[id*='grid']");
  console.log('📋 Elements with "grid" in id:', gridElements.length);
  gridElements.forEach((el, i) => {
    console.log(`📋   Grid element ${i}: tag=${el.tagName} id="${el.getAttribute('id')}"`);
  });
  
  // Look for assignment-related content
  const assignmentLinks = root.querySelectorAll("a[id*='Assignment']");
  const showAssignmentLinks = root.querySelectorAll("a[id='showAssignmentInfo']");
  console.log('📋 Assignment-related links:', assignmentLinks.length);
  console.log('📋 showAssignmentInfo links:', showAssignmentLinks.length);
  
  // Check course heading
  const courseHeading = root.querySelector("h2.gb_heading");
  console.log('📋 Course heading found:', !!courseHeading);
  if (courseHeading) {
    console.log('📋 Course heading HTML:', courseHeading.innerHTML.substring(0, 200));
  }
  
  // Save HTML to console for manual inspection
  if (html.length < 50000) {
    console.log('📋 FULL HTML CONTENT (first 2000 chars):', html.substring(0, 2000));
  }
  
  console.log('📋 === END HTML ANALYSIS ===');
  
  // Helpers - EXACT backend match
  const clean = (txt = "") => txt.replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();
  const toInt = (txt: string) => {
    const m = clean(txt).match(/^-?\d+/);
    return m ? parseInt(m[0], 10) : null;
  };
  const toFloat = (txt: string) => {
    const m = clean(txt).match(/-?\d+(?:\.\d+)?/);
    return m ? parseFloat(m[0]) : null;
  };

  // Course, period, instructor - EXACT backend match
  const courseLink = root.querySelector("h2.gb_heading a");
  const periodText = root.querySelector("h2.gb_heading span.fXs b")?.textContent;
  const instructorLinks = root.querySelectorAll("h2.gb_heading a");
  const instructorLink = instructorLinks.length > 1 ? instructorLinks[1] : null;
  const course = clean(courseLink?.textContent || "");
  const period = toInt(periodText || "");
  const instructor = clean(instructorLink?.textContent || "");

  console.log('📋 Parsed course info:', { course, instructor, period });

  // Lit info - ADAPTED for DIV structure
  let litHeader = root.querySelector("table[id^='grid_stuTermSummaryGrid'] thead th");
  if (!litHeader) {
    // Look in div structure
    const termGrid = root.querySelector("div[id*='stuTermSummaryGrid']");
    if (termGrid) {
      litHeader = termGrid.querySelector("thead th") || termGrid.querySelector("th");
    }
  }
  
  // Prefer the text before the <span> (e.g., "PR1 Grade"); fall back to full text
  const litHeaderText = clean(litHeader?.childNodes?.[0]?.textContent || litHeader?.textContent || "");
  const litName = litHeaderText.replace(/Grade\s*$/, "").trim();
  const dateMatch = (litHeader?.querySelector("span")?.textContent || "").match(/(\d{2}\/\d{2}\/\d{4})\s*-\s*(\d{2}\/\d{2}\/\d{4})/);
  const lit = {
    name: litName,
    begin: dateMatch ? dateMatch[1] : null,
    end: dateMatch ? dateMatch[2] : null,
  };

  console.log('📋 Parsed lit info:', lit);

  // Summary score - ADAPTED for DIV structure
  let summaryRow = root.querySelector("table[id^='grid_stuTermSummaryGrid'] tbody tr[class]:not(.sf_Section)");
  if (!summaryRow) {
    // Look in div structure
    const termGrid = root.querySelector("div[id*='stuTermSummaryGrid']");
    if (termGrid) {
      summaryRow = termGrid.querySelector("tbody tr[class]:not(.sf_Section)") || termGrid.querySelector("tbody tr");
    }
  }
  
  const topScore = toFloat(summaryRow?.querySelector("td:last-child")?.textContent || "");
  const topGrade = topScore != null ? Math.round(topScore) : null;

  console.log('📋 Parsed summary:', { topScore, topGrade });

  // Gradebook (categories + assignments) - ADAPTED for DIV-based structure
  const gradebook: GradeCategory[] = [];
  
  // First try the backend's table-based approach
  let rows = [...root.querySelectorAll("table[id^='grid_stuAssignmentSummaryGrid'] tbody tr")];
  
  // If no table rows found, look for div-based structure
  if (rows.length === 0) {
    console.log('📋 No table rows found, looking for div-based structure...');
    
    // Find the assignment grid container
    const assignmentGrid = root.querySelector("div[id*='stuAssignmentSummaryGrid']");
    if (assignmentGrid) {
      console.log('📋 Found assignment grid div:', assignmentGrid.getAttribute('id'));
      // Look for tr elements anywhere within the grid div
      rows = [...assignmentGrid.querySelectorAll("tr")];
      console.log('📋 Found', rows.length, 'rows in div structure');
    }
    
    // If still no rows, look for all tr elements that contain assignment links
    if (rows.length === 0) {
      console.log('📋 Looking for rows with assignment links...');
      const allTrs = root.querySelectorAll("tr");
      rows = [...allTrs].filter(tr => 
        tr.querySelector("a[id='showAssignmentInfo']") || 
        (tr.classList.contains("sf_Section") && tr.classList.contains("cat"))
      );
      console.log('📋 Found', rows.length, 'rows with assignment content');
    }
  }
  
  let currentCategory: GradeCategory | null = null;
  let lastMainCategory: GradeCategory | null = null;
  let rcWeights: any[] = [];
  let afterBoldCategory = false;

  console.log('📋 Processing', rows.length, 'gradebook rows');
  
  // Debug each row type
  rows.forEach((row, idx) => {
    const hasShowAssignmentInfo = !!row.querySelector("a[id='showAssignmentInfo']");
    const isSectionCat = row.classList.contains("sf_Section") && row.classList.contains("cat");
    const cellCount = row.querySelectorAll("td").length;
    
    if (idx < 5 || hasShowAssignmentInfo || isSectionCat) {
      console.log(`📋 Row ${idx}: showAssignmentInfo=${hasShowAssignmentInfo}, sectionCat=${isSectionCat}, cells=${cellCount}`);
      if (hasShowAssignmentInfo) {
        const link = row.querySelector("a[id='showAssignmentInfo']");
        console.log(`📋   Assignment: "${clean(link?.textContent || "")}" - first 200 chars: ${row.innerHTML.substring(0, 200)}`);
      }
      if (isSectionCat) {
        const cells = row.querySelectorAll("td");
        const categoryText = clean(cells[1]?.textContent || "");
        console.log(`📋   Category: "${categoryText}" - first 200 chars: ${row.innerHTML.substring(0, 200)}`);
      }
    }
  });

  rows.forEach((row, idx) => {
    // Debug: log row type and content - EXACT backend match
    if (row.classList.contains("sf_Section") && row.classList.contains("cat")) {
      const cells = row.querySelectorAll("td");
      const nameNode = cells[1]?.childNodes?.[0];
      const rawName = clean(nameNode?.textContent || cells[1]?.textContent || "");
      
      // EXACT backend font-weight detection
      const styleAttr = cells[1]?.getAttribute("style") || "";
      const isBold = cells[1]?.getAttribute("style")?.includes("font-weight:bold") || 
                     /font-weight:\s*bold/i.test(styleAttr);
      
      // Find weight in any span in the cell - EXACT backend match
      let weightMatch: RegExpMatchArray | null = null;
      let foundWeightSpan = '';
      const spans = cells[1]?.querySelectorAll("span") || [];
      for (const span of spans) {
        const txt = clean(span.textContent || "");
        const match = txt.match(/weighted at ([\d.]+)%(?:, adjusted to ([\d.]+)%)?/i);
        if (match) {
          weightMatch = match;
          foundWeightSpan = txt;
          break;
        }
      }
      
      console.log('📋 Category row:', { rawName, isBold, weightMatch: !!weightMatch, foundWeightSpan });
      
      if (isBold) {
        lastMainCategory = {
          category: rawName,
          weight: null,
          adjustedWeight: null,
          assignments: [],
        };
        afterBoldCategory = true;
        // If weight is present in the bold row, use it
        if (weightMatch) {
          lastMainCategory.weight = parseFloat(weightMatch[1]);
          lastMainCategory.adjustedWeight = weightMatch[2] ? parseFloat(weightMatch[2]) : null;
        }
        gradebook.push(lastMainCategory);
        currentCategory = lastMainCategory;
        console.log('📋 Added bold category:', rawName);
        return;
      }

      // If this is RC1 or RC2 after a bold category - EXACT backend match
      if (/RC\d/i.test(rawName) && afterBoldCategory) {
        console.log('📋 Processing RC category:', rawName);
        // Use the span search weightMatch for RC rows
        // Always assign RC1 weight to the last main category if not set
        if (/RC1/i.test(rawName) && weightMatch && lastMainCategory && lastMainCategory.weight == null) {
          lastMainCategory.weight = parseFloat(weightMatch[1]);
          lastMainCategory.adjustedWeight = weightMatch[2] ? parseFloat(weightMatch[2]) : null;
        }
        // If RC2 comes first, store its weight and assign after RC1
        if (/RC2/i.test(rawName) && weightMatch && lastMainCategory && lastMainCategory.weight == null) {
          (lastMainCategory as any)._pendingWeight = {
            weight: parseFloat(weightMatch[1]),
            adjustedWeight: weightMatch[2] ? parseFloat(weightMatch[2]) : null,
          };
        }
        // If RC1 comes and RC2 weight was stored, use RC1 weight, else use RC2
        if (/RC1/i.test(rawName) && lastMainCategory && lastMainCategory.weight == null && (lastMainCategory as any)._pendingWeight) {
          // Prefer RC1 weight if available, else RC2
          lastMainCategory.weight = parseFloat(weightMatch![1]);
          lastMainCategory.adjustedWeight = weightMatch![2] ? parseFloat(weightMatch![2]) : (lastMainCategory as any)._pendingWeight.adjustedWeight;
          delete (lastMainCategory as any)._pendingWeight;
        }
        // Do NOT push RC1/RC2 as categories
        return;
      }

      // If not bold and not RC1/RC2, treat as normal category - EXACT backend match
      currentCategory = {
        category: rawName,
        weight: weightMatch ? parseFloat(weightMatch[1]) : null,
        adjustedWeight: weightMatch && weightMatch[2] ? parseFloat(weightMatch[2]) : null,
        assignments: [],
      };
      gradebook.push(currentCategory);
      afterBoldCategory = false;
      console.log('📋 Added normal category:', rawName);
      return;
    }

    // Assignment row - EXACT backend match
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
      
      // Debug logging for metadata cells
      console.log('🏷️ === METADATA EXTRACTION DEBUG ===');
      console.log(`🏷️ Assignment: "${name}"`);
      console.log(`🏷️ Total cells in row: ${cells.length}`);
      
      // Print the FULL HTML for this specific assignment if it matches the one you're interested in
      if (name.includes("CANs #50&54") || name.includes("CAN")) {
        console.log('🏷️ 🎯 FULL HTML FOR TARGET ASSIGNMENT:');
        console.log('🏷️ Row HTML:', row.outerHTML);
        console.log('🏷️ --- END FULL HTML ---');
      }
      
      // Log all cell contents for debugging
      cells.forEach((cell, cellIdx) => {
        const cellText = clean(cell.textContent || "");
        const tooltip = cell.getAttribute('tooltip');
        const hasTooltip = !!tooltip;
        const cellHTML = cell.outerHTML;
        console.log(`🏷️ Cell ${cellIdx}: text="${cellText}" hasTooltip=${hasTooltip} tooltip="${tooltip || 'none'}"`);
        
        // For the target assignment, also print cell HTML
        if (name.includes("CANs #50&54") || name.includes("CAN")) {
          console.log(`🏷️ 🎯 Cell ${cellIdx} HTML:`, cellHTML);
        }
      });
      
      // Extract metadata from specific cells with detailed logging
      const missingTooltip = cells[5]?.getAttribute('tooltip');
      console.log('🏷️ Cell 5 (Missing) - tooltip:', missingTooltip || 'none');
      if (missingTooltip) {
        meta.push({ type: "missing", note: missingTooltip });
        console.log('🏷️ ✓ Added MISSING metadata:', missingTooltip);
      }
      
      const noCountTooltip = cells[6]?.getAttribute('tooltip');
      console.log('🏷️ Cell 6 (No Count) - tooltip:', noCountTooltip || 'none');
      if (noCountTooltip) {
        meta.push({ type: "noCount", note: noCountTooltip });
        console.log('🏷️ ✓ Added NO COUNT metadata:', noCountTooltip);
      }
      
      const absentTooltip = cells[7]?.getAttribute('tooltip');
      const absentText = cells[7]?.textContent?.trim() || '';
      console.log('🏷️ Cell 7 (Absent) - tooltip:', absentTooltip || 'none');
      console.log('🏷️ Cell 7 (Absent) - text content:', absentText || 'none');
      
      if (absentTooltip) {
        meta.push({ type: "absent", note: absentTooltip });
        console.log('🏷️ ✓ Added ABSENT metadata from tooltip:', absentTooltip);
      } else if (absentText && absentText !== '' && absentText !== '\u00A0' && !absentText.includes('out of')) {
        // Cell 7 has meaningful text content that could be an absent message
        meta.push({ type: "absent", note: absentText });
        console.log('🏷️ ✓ Added ABSENT metadata from text content:', absentText);
      }
      
      // Also check for any other cells that might have tooltips
      console.log('🏷️ Checking ALL cells for any tooltips:');
      cells.forEach((cell, cellIdx) => {
        const tooltip = cell.getAttribute('tooltip');
        if (tooltip && cellIdx !== 5 && cellIdx !== 6 && cellIdx !== 7) {
          console.log(`🏷️ ⚠️ Unexpected tooltip found in cell ${cellIdx}: "${tooltip}"`);
        }
      });
      
      console.log('🏷️ Final metadata array:', meta);
      console.log('🏷️ === END METADATA DEBUG ===');
      
      currentCategory.assignments.push({
        date,
        name,
        grade: assignmentGrade,
        score: assignmentScore,
        points,
        meta,
      });
      
      console.log('📋 Added assignment:', name, 'to category:', currentCategory.category);
    }

    // If next row is not RC1/RC2 or end of rows, assign RC weights to main category if needed - EXACT backend match
    const nextRow = rows[idx + 1];
    const isNextRC = nextRow && nextRow.classList.contains("sf_Section") && nextRow.classList.contains("cat") &&
      /RC\d/i.test(clean(nextRow.querySelectorAll("td")[1]?.textContent || ""));
    if (lastMainCategory && lastMainCategory.weight == null && rcWeights.length > 0 && !isNextRC) {
      const firstWeight = rcWeights.find(w => w.weight != null);
      if (firstWeight) {
        lastMainCategory.weight = firstWeight.weight;
        lastMainCategory.adjustedWeight = firstWeight.adjustedWeight;
      }
      rcWeights = [];
      afterBoldCategory = false;
    }
  });

  // After all rows, if lastMainCategory still has no weight and rcWeights collected, assign it - EXACT backend match
  if (lastMainCategory && (lastMainCategory as GradeCategory).weight == null && rcWeights.length > 0) {
    const firstWeight = rcWeights.find((w: any) => w.weight != null);
    if (firstWeight && lastMainCategory) {
      (lastMainCategory as GradeCategory).weight = firstWeight.weight;
      (lastMainCategory as GradeCategory).adjustedWeight = firstWeight.adjustedWeight;
    }
    rcWeights = [];
  }

  // Filter out categories weighted at 0.00% and with no assignments - EXACT backend match
  const filteredGradebook = gradebook.filter(cat => !(cat.weight === 0 && (!cat.assignments || cat.assignments.length === 0)));

  console.log('📋 Final gradebook:', filteredGradebook.length, 'categories');
  filteredGradebook.forEach(cat => {
    console.log(`📋 Category: ${cat.category}, Weight: ${cat.weight}%, Assignments: ${cat.assignments.length}`);
  });

  return {
    course,
    instructor,
    lit,
    period,
    score: topScore,
    grade: topGrade,
    gradebook: filteredGradebook,
  };
};

// ===== MAIN EXPORT FUNCTION =====
export const fetchGradeInfoDirect = async (params: GradeInfoParams, url?: string): Promise<GradeInfoResult> => {
  try {
    console.log('📋 Starting grade info fetch with params:', params);
    
    // Get base URL if not provided
    if (!url) {
      const storedUrl = await AsyncStorage.getItem('skywardBaseURL');
      if (!storedUrl) {
        throw new Error('No Skyward base URL found in storage');
      }
      url = storedUrl;
    }

    console.log('📋 Base URL:', url);
    
    // Fetch HTML
    const html = await fetchGradeInfoHTML(params, url);
    
    // Parse HTML using EXACT backend function
    const result = parseGradeInfo(html);
    
    console.log('✅ Grade info fetch completed successfully');
    return result;
    
  } catch (error: any) {
    console.error('❌ Error in fetchGradeInfoDirect:', error.message);
    throw error;
  }
};

export { extractCourseExtraInfo };
