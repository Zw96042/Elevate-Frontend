import fs from 'node:fs';
import path from 'node:path';

const sensitivePaths = [
  'utils/calculateGrades.tsx',
  'app/classes/[class].tsx',
  'app/enterGrades/[gradeLevel].tsx',
  'app/(tabs)/gpa.tsx',
];

describe('production academic-data logging', () => {
  it.each(sensitivePaths)('%s has no direct executable console output', relativePath => {
    const source = fs.readFileSync(path.resolve(__dirname, '../..', relativePath), 'utf8');
    const executableLines = source
      .split('\n')
      .filter(line => !line.trimStart().startsWith('//'))
      .join('\n');

    expect(executableLines).not.toMatch(/console\.(?:log|warn|error)\s*\(/);
  });
});
