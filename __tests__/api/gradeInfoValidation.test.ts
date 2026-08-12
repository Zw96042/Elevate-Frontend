import { parseGradeInfoHTML } from '../../lib/api/skyward/grades';

const validEmpty = `
  <h2 class="gb_heading"><a>Algebra II</a><a>Ms. Rivera</a></h2>
  <table id="grid_stuTermSummaryGrid_1">
    <thead><tr><th>Q1 Grade</th></tr></thead>
    <tbody><tr class="grade"><td>Q1</td><td></td></tr></tbody>
  </table>
  <table id="grid_stuAssignmentSummaryGrid_1"><tbody></tbody></table>
`;

describe('Skyward grade-info validation', () => {
  it('preserves a structurally valid empty gradebook', () => {
    expect(parseGradeInfoHTML(validEmpty)).toMatchObject({
      course: 'Algebra II',
      lit: { name: 'Q1' },
      gradebook: [],
    });
  });

  it.each([
    '<html><body>Maintenance in progress</body></html>',
    '<html>Family Access<form><input name="password"></form></html>',
  ])('rejects arbitrary successful HTML instead of caching an empty gradebook', html => {
    expect(() => parseGradeInfoHTML(html)).toThrow(/grade response/);
  });

  it('rejects malformed category rows', () => {
    const malformed = validEmpty.replace(
      '<tbody></tbody>',
      '<tbody><tr class="sf_Section cat"><td>truncated</td></tr></tbody>'
    );
    expect(() => parseGradeInfoHTML(malformed)).toThrow(/category row/);
  });

  it('preserves zero but drops oversized numeric fields', () => {
    const huge = '9'.repeat(400);
    const html = validEmpty
      .replace('<td></td></tr></tbody>', `<td>${huge}</td></tr></tbody>`)
      .replace(
        '<tbody></tbody>',
        `<tbody>
          <tr class="sf_Section cat"><td></td><td style="font-weight: bold">Tests <span>weighted at ${huge}%</span></td></tr>
          <tr><td>08/20/2026</td><td><a id="showAssignmentInfo">Zero</a></td><td>0</td><td>${huge}</td><td>${huge} out of ${huge}</td></tr>
        </tbody>`
      );
    const result = parseGradeInfoHTML(html);
    expect(result).toMatchObject({ score: null, grade: null });
    expect(result.gradebook[0]).toMatchObject({ weight: null });
    expect(result.gradebook[0].assignments[0]).toMatchObject({
      grade: 0,
      score: null,
      points: null,
    });
  });

  it('rejects scientific-notation prefixes instead of parsing them as one', () => {
    const html = validEmpty
      .replace('<td></td></tr></tbody>', '<td>1e308</td></tr></tbody>')
      .replace(
        '<tbody></tbody>',
        `<tbody>
          <tr class="sf_Section cat"><td></td><td style="font-weight: bold">Tests <span>weighted at 1e308%</span></td></tr>
          <tr><td>08/20/2026</td><td><a id="showAssignmentInfo">Malformed</a></td><td>1e308</td><td>1e308</td><td>1e308 out of 1e308</td></tr>
        </tbody>`
      );
    const result = parseGradeInfoHTML(html);
    expect(result).toMatchObject({ score: null, grade: null });
    expect(result.gradebook[0]).toMatchObject({ weight: null });
    expect(result.gradebook[0].assignments[0]).toMatchObject({
      grade: null,
      score: null,
      points: null,
    });
  });
});
