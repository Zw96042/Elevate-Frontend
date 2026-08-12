import axios from 'axios';
import {
  combineAcademicData,
  fetchAcademicHistory,
  fetchCombinedAcademicData,
  parseGradebookHTML,
} from '../../lib/api/skyward/academic-history';

jest.mock('axios', () => {
  const request = jest.fn();
  return {
    __esModule: true,
    default: Object.assign(request, { post: jest.fn() }),
  };
});

jest.mock('../../lib/utils/logger', () => ({
  logger: {
    debug: jest.fn(),
    info: jest.fn(),
    success: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
  Modules: { API_HISTORY: 'API:History' },
  log: {
    api: {
      request: jest.fn(),
      success: jest.fn(),
      error: jest.fn(),
    },
  },
}));

const sessionCodes = {
  dwd: 'dwd',
  wfaacl: 'wfaacl',
  encses: 'encses',
  'User-Type': 'guardian',
  sessionid: 'session',
};

const wrapGridLiteral = (literal: string) => `<script>
  sff.sv('sf_gridObjects', $.extend((sff.getValue('sf_gridObjects') || {}), ${literal}));
</script>`;

describe('Skyward grid parsing', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('keeps valid gradebook object literals working', async () => {
    const html = wrapGridLiteral('{stuGradesGrid_1_2:{tb:{r:[]}}}');
    await expect(parseGradebookHTML(html)).resolves.toEqual({ data: [], raw: html });
  });

  it('rejects arbitrary successful HTML instead of returning authoritative empty courses', async () => {
    await expect(parseGradebookHTML('<html><body>Maintenance</body></html>')).rejects.toThrow(
      /no grid data/
    );
  });

  it('rejects executable gradebook expressions without running them', async () => {
    const executionState = globalThis as typeof globalThis & { __skywardGradebookExecuted?: boolean };
    executionState.__skywardGradebookExecuted = false;
    const html = wrapGridLiteral(
      '{stuGradesGrid_1_2:(function(){globalThis.__skywardGradebookExecuted=true})()}'
    );

    await expect(parseGradebookHTML(html)).rejects.toThrow(/unsupported expression/);
    expect(executionState.__skywardGradebookExecuted).toBe(false);
  });

  it('rejects executable academic-history expressions without running them', async () => {
    const executionState = globalThis as typeof globalThis & { __skywardHistoryExecuted?: boolean };
    executionState.__skywardHistoryExecuted = false;
    const html = wrapGridLiteral(
      '{gradeGrid_1_2_3:(function(){globalThis.__skywardHistoryExecuted=true})()}'
    );
    (axios as unknown as jest.Mock).mockResolvedValue({ data: html });

    await expect(fetchAcademicHistory('https://example.test/', sessionCodes)).rejects.toThrow(
      /unsupported expression/
    );
    expect(executionState.__skywardHistoryExecuted).toBe(false);
  });

  it('accepts a verified no-history page without inventing a grid', async () => {
    (axios as unknown as jest.Mock).mockResolvedValue({
      data: '<html><head><title>Academic History</title></head><body>No records</body></html>',
    });
    await expect(fetchAcademicHistory('https://example.test/', sessionCodes)).resolves.toEqual({});
  });

  it('rejects a same-title maintenance page without an explicit empty marker', async () => {
    (axios as unknown as jest.Mock).mockResolvedValue({
      data: '<html><head><title>Academic History</title></head><body>Maintenance</body></html>',
    });
    await expect(fetchAcademicHistory('https://example.test/', sessionCodes)).rejects.toThrow(
      /No academic history data found/
    );
  });

  it.each([
    '{otherGrid:{tb:{r:[]}}}',
    '{gradeGrid_1_2_3:{tb:{}}}',
    '{gradeGrid_1_2_3:{tb:{r:[{}]}}}',
  ])('rejects incompatible or incomplete academic-history grids', async literal => {
    (axios as unknown as jest.Mock).mockResolvedValue({ data: wrapGridLiteral(literal) });
    await expect(fetchAcademicHistory('https://example.test/', sessionCodes)).rejects.toThrow(
      /compatible grade grid|grade grid was incomplete|unrecognized populated rows/
    );
  });

  it('rejects a year header followed only by a malformed course row', async () => {
    const literal = `{gradeGrid_1_2_3:{tb:{r:[
      {c:[{h:'2025 - 2026 Grade 11'}]},
      {c:[{}]}
    ]}}}`;
    (axios as unknown as jest.Mock).mockResolvedValue({ data: wrapGridLiteral(literal) });
    await expect(fetchAcademicHistory('https://example.test/', sessionCodes)).rejects.toThrow(
      /malformed populated rows/
    );
  });

  it('rejects truncated course rows and invalid academic-year headers', async () => {
    for (const literal of [
      `{gradeGrid_1_2_3:{tb:{r:[
        {c:[{h:'2025 - 2026 Grade 11'}]},
        {c:[{h:'<a>Biology</a>'},{h:'1 - 4'}]}
      ]}}}`,
      `{gradeGrid_1_2_3:{tb:{r:[{c:[{h:'2025 - 2027 Grade 11'}]}]}}}`,
      `{gradeGrid_1_2_3:{tb:{r:[{c:[{h:'2025 - 2026 Grade 99'}]}]}}}`,
    ]) {
      (axios as unknown as jest.Mock).mockResolvedValue({ data: wrapGridLiteral(literal) });
      await expect(fetchAcademicHistory('https://example.test/', sessionCodes)).rejects.toThrow(
        /malformed populated rows|invalid year header/
      );
    }
  });

  it('accepts but omits a valid Grade 8 credit section beside Grade 9', async () => {
    const blanks = Array.from({ length: 16 }, () => ({ h: '' }));
    const literal = JSON.stringify({
      gradeGrid_1_2_3: { tb: { r: [
        { c: [{ h: '2024 - 2025 Grade 8' }] },
        { c: [{ h: '<a>Algebra I</a>' }, { h: '1 - 4' }, ...blanks] },
        { c: [{ h: '2025 - 2026 Grade 9' }] },
        { c: [{ h: '<a>Biology</a>' }, { h: '1 - 4' }, ...blanks] },
      ] } },
    });
    (axios as unknown as jest.Mock).mockResolvedValue({ data: wrapGridLiteral(literal) });

    await expect(fetchAcademicHistory('https://example.test/', sessionCodes)).resolves.toEqual({
      '2025-2026': expect.objectContaining({
        grade: 9,
        courses: expect.objectContaining({ Biology: expect.any(Object) }),
      }),
    });
  });

  it('rejects malformed populated current-gradebook rows', async () => {
    const html = wrapGridLiteral('{stuGradesGrid_1_2:{tb:{r:[{}]}}}');
    await expect(parseGradebookHTML(html)).rejects.toThrow(/unrecognized populated rows/);
  });

  it('keeps a course identity without turning an unposted blank bucket into zero', async () => {
    const html = wrapGridLiteral(`{stuGradesGrid_1_2:{tb:{r:[{c:[{
      cId:'course',
      h:'<a data-cni="42" data-bkt="TERM 1" data-gid="GB">   </a>'
    }]}]}}}`);
    await expect(parseGradebookHTML(html)).resolves.toEqual(expect.objectContaining({
      data: [expect.objectContaining({ course: 42, scores: [] })],
    }));
  });

  it('keeps current courses when the student has no academic history', () => {
    const result = combineAcademicData({}, {
      data: [{
        course: 42,
        courseName: 'Biology',
        scores: [{ bucket: 'TERM 3', score: 91 }],
      }],
    }, 9);

    expect(result.current.grade).toBe(9);
    expect(result.current.courses.Biology).toEqual(expect.objectContaining({
      courseId: 42,
      rc1: 91,
    }));
  });

  it('retains unmatched history and starts a new year when the grade changes', () => {
    const history = {
      '2025-2026': {
        grade: 9,
        courses: {
          'Completed Art': { terms: '1 - 2', finalGrade: '94' },
        },
      },
    };
    const result = combineAcademicData(history, {
      data: [{ course: 43, courseName: 'Geometry', scores: [] }],
    }, 10);

    expect(result['2025-2026'].courses['Completed Art']).toBeDefined();
    expect(result['2026-2027'].grade).toBe(10);
    expect(result['2026-2027'].courses.Geometry).toBeDefined();
  });

  it('does not duplicate slow parallel combined-data requests', async () => {
    let resolveHistory!: (value: any) => void;
    let resolveGradebook!: (value: any) => void;
    const historyRequest = new Promise(resolve => { resolveHistory = resolve; });
    const gradebookRequest = new Promise(resolve => { resolveGradebook = resolve; });
    (axios as unknown as jest.Mock).mockReturnValue(historyRequest);
    (axios.post as jest.Mock).mockReturnValue(gradebookRequest);

    const pending = fetchCombinedAcademicData('https://example.test/', sessionCodes);
    expect(axios).toHaveBeenCalledTimes(1);
    expect(axios.post).toHaveBeenCalledTimes(1);

    resolveHistory({
      data: '<html><head><title>Academic History</title></head><body>No records</body></html>',
    });
    resolveGradebook({ data: wrapGridLiteral('{stuGradesGrid_1_2:{tb:{r:[]}}}') });

    await expect(pending).resolves.toEqual({});
    expect(axios).toHaveBeenCalledTimes(1);
    expect(axios.post).toHaveBeenCalledTimes(1);
  });
});
