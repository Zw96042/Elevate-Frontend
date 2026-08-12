const MAXIMUM_INPUT_LENGTH = 5_000_000;
const MAXIMUM_DEPTH = 128;
const MAXIMUM_VALUES = 250_000;

/**
 * Parses the data-only subset of JavaScript literals used by Skyward grids.
 * Expressions, calls, property access, and trailing executable text are rejected.
 */
export function parseJavaScriptLiteral(source: string): unknown {
  if (source.length > MAXIMUM_INPUT_LENGTH) {
    throw new Error('Skyward data was too large to parse safely');
  }

  return new JavaScriptLiteralParser(source).parse();
}

class JavaScriptLiteralParser {
  private index = 0;
  private depth = 0;
  private valueCount = 0;

  constructor(private readonly source: string) {}

  parse(): unknown {
    const value = this.parseValue();
    this.skipTrivia();
    if (!this.isAtEnd()) {
      this.unsupported();
    }
    return value;
  }

  private parseValue(): unknown {
    this.skipTrivia();
    this.recordValue();

    const character = this.current();
    if (character === undefined) {
      throw new Error('Skyward data ended unexpectedly');
    }

    if (character === '{') return this.parseObject();
    if (character === '[') return this.parseArray();
    if (character === '"' || character === "'") return this.parseString();
    if (character === '+' || character === '-' || character === '.' || this.isDigit(character)) {
      return this.parseNumber();
    }

    const identifier = this.parseIdentifier();
    switch (identifier) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
      case 'undefined':
      case 'NaN':
      case 'Infinity':
        return null;
      default:
        return identifier;
    }
  }

  private parseObject(): Record<string, unknown> {
    this.enterContainer();
    this.advance();

    try {
      this.skipTrivia();
      const object: Record<string, unknown> = Object.create(null);
      if (this.consume('}')) return object;

      while (true) {
        this.skipTrivia();
        const character = this.current();
        if (character === undefined) {
          throw new Error('Skyward data ended unexpectedly');
        }

        let key: string;
        if (character === '"' || character === "'") {
          key = this.parseString();
        } else if (
          character === '+' ||
          character === '-' ||
          character === '.' ||
          this.isDigit(character)
        ) {
          key = String(this.parseNumber());
        } else {
          key = this.parseIdentifier();
        }

        this.skipTrivia();
        if (!this.consume(':')) this.unsupported();
        object[key] = this.parseValue();
        this.skipTrivia();

        if (this.consume('}')) return object;
        if (!this.consume(',')) this.unsupported();
        this.skipTrivia();
        if (this.consume('}')) return object;
      }
    } finally {
      this.depth -= 1;
    }
  }

  private parseArray(): unknown[] {
    this.enterContainer();
    this.advance();

    try {
      this.skipTrivia();
      const array: unknown[] = [];
      if (this.consume(']')) return array;

      while (true) {
        this.skipTrivia();
        if (this.consume(']')) return array;
        if (this.consume(',')) {
          this.recordValue();
          array.push(null);
          continue;
        }

        array.push(this.parseValue());
        this.skipTrivia();
        if (this.consume(']')) return array;
        if (!this.consume(',')) this.unsupported();
        this.skipTrivia();
        if (this.consume(']')) return array;
      }
    } finally {
      this.depth -= 1;
    }
  }

  private parseString(): string {
    const quote = this.current();
    if (quote !== '"' && quote !== "'") this.unsupported();
    this.advance();

    let result = '';
    while (!this.isAtEnd()) {
      const character = this.current()!;
      this.advance();

      if (character === quote) return result;
      if (character === '\n' || character === '\r') this.unsupported();
      if (character !== '\\') {
        result += character;
        continue;
      }

      const escaped = this.current();
      if (escaped === undefined) {
        throw new Error('Skyward data ended unexpectedly');
      }
      this.advance();

      switch (escaped) {
        case '"':
        case "'":
        case '\\':
        case '/':
          result += escaped;
          break;
        case 'b':
          result += '\b';
          break;
        case 'f':
          result += '\f';
          break;
        case 'n':
          result += '\n';
          break;
        case 'r':
          result += '\r';
          break;
        case 't':
          result += '\t';
          break;
        case 'v':
          result += '\v';
          break;
        case '\n':
          break;
        case '\r':
          if (this.current() === '\n') this.advance();
          break;
        case 'x':
          result += this.parseEscapedCharacter(2);
          break;
        case 'u':
          result += this.parseEscapedCharacter(4);
          break;
        default:
          result += escaped;
      }
    }

    throw new Error('Skyward data ended unexpectedly');
  }

  private parseEscapedCharacter(digits: number): string {
    let hexadecimal = '';
    for (let offset = 0; offset < digits; offset += 1) {
      const character = this.current();
      if (character === undefined || !/[0-9A-Fa-f]/.test(character)) {
        throw new Error('Skyward data contained an invalid string escape');
      }
      hexadecimal += character;
      this.advance();
    }
    return String.fromCharCode(Number.parseInt(hexadecimal, 16));
  }

  private parseNumber(): number {
    const start = this.index;
    if (this.current() === '+' || this.current() === '-') this.advance();

    let digitCount = 0;
    while (this.current() !== undefined && this.isDigit(this.current()!)) {
      digitCount += 1;
      this.advance();
    }

    if (this.current() === '.') {
      this.advance();
      while (this.current() !== undefined && this.isDigit(this.current()!)) {
        digitCount += 1;
        this.advance();
      }
    }

    if (digitCount === 0) {
      throw new Error('Skyward data contained an invalid number');
    }

    if (this.current() === 'e' || this.current() === 'E') {
      this.advance();
      if (this.current() === '+' || this.current() === '-') this.advance();
      const exponentStart = this.index;
      while (this.current() !== undefined && this.isDigit(this.current()!)) this.advance();
      if (exponentStart === this.index) {
        throw new Error('Skyward data contained an invalid number');
      }
    }

    const value = Number(this.source.slice(start, this.index));
    if (!Number.isFinite(value)) {
      throw new Error('Skyward data contained an invalid number');
    }
    return value;
  }

  private parseIdentifier(): string {
    const first = this.current();
    if (first === undefined || !this.isIdentifierStart(first)) this.unsupported();

    const start = this.index;
    this.advance();
    while (this.current() !== undefined && this.isIdentifierContinuation(this.current()!)) {
      this.advance();
    }
    return this.source.slice(start, this.index);
  }

  private skipTrivia(): void {
    while (true) {
      while (this.current() !== undefined && /\s/.test(this.current()!)) this.advance();
      if (this.current() !== '/' || (this.peek() !== '/' && this.peek() !== '*')) return;

      const lineComment = this.peek() === '/';
      this.advance();
      this.advance();

      if (lineComment) {
        while (this.current() !== undefined && this.current() !== '\n' && this.current() !== '\r') {
          this.advance();
        }
      } else {
        while (this.current() !== undefined && !(this.current() === '*' && this.peek() === '/')) {
          this.advance();
        }
        if (this.current() === undefined) {
          throw new Error('Skyward data ended unexpectedly');
        }
        this.advance();
        this.advance();
      }
    }
  }

  private enterContainer(): void {
    this.depth += 1;
    if (this.depth > MAXIMUM_DEPTH) {
      throw new Error('Skyward data was nested too deeply');
    }
  }

  private recordValue(): void {
    this.valueCount += 1;
    if (this.valueCount > MAXIMUM_VALUES) {
      throw new Error('Skyward data contained too many values');
    }
  }

  private current(): string | undefined {
    return this.source[this.index];
  }

  private peek(): string | undefined {
    return this.source[this.index + 1];
  }

  private advance(): void {
    this.index += 1;
  }

  private consume(expected: string): boolean {
    if (this.current() !== expected) return false;
    this.advance();
    return true;
  }

  private isAtEnd(): boolean {
    return this.index >= this.source.length;
  }

  private isDigit(character: string): boolean {
    return character >= '0' && character <= '9';
  }

  private isIdentifierStart(character: string): boolean {
    return /[A-Za-z_$]/.test(character);
  }

  private isIdentifierContinuation(character: string): boolean {
    return this.isIdentifierStart(character) || this.isDigit(character);
  }

  private unsupported(): never {
    throw new Error('Skyward data contained an unsupported expression');
  }
}
