import { parseJavaScriptLiteral } from '../../lib/utils/javascript-literal-parser';

describe('parseJavaScriptLiteral', () => {
  it('parses Skyward-style data literals without evaluating them', () => {
    const parsed = parseJavaScriptLiteral(`{
      grid: {
        tb: { r: [{ c: [{ h: '<b>Algebra</b>' }], },], },
      },
      enabled: true,
      missing: undefined,
      // Skyward payloads can contain comments and trailing commas.
    }`) as Record<string, unknown>;

    expect(parsed.enabled).toBe(true);
    expect(parsed.missing).toBeNull();
    expect(parsed.grid).toEqual({
      tb: { r: [{ c: [{ h: '<b>Algebra</b>' }] }] },
    });
  });

  it.each([
    '{value:(function(){globalThis.__skywardParserExecuted=true})()}',
    '{value:globalThis.process}',
    '{value:1}; globalThis.__skywardParserExecuted=true',
    '{value:()=>1}',
  ])('rejects executable input: %s', source => {
    (globalThis as typeof globalThis & { __skywardParserExecuted?: boolean }).__skywardParserExecuted = false;

    expect(() => parseJavaScriptLiteral(source)).toThrow(/unsupported expression/);
    expect(
      (globalThis as typeof globalThis & { __skywardParserExecuted?: boolean }).__skywardParserExecuted
    ).toBe(false);
  });

  it('rejects excessive nesting', () => {
    const source = `${'['.repeat(129)}${']'.repeat(129)}`;
    expect(() => parseJavaScriptLiteral(source)).toThrow(/nested too deeply/);
  });
});
