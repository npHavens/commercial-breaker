// Blank-line rules only: no correctness or layout checks. `npm run lint -- --fix` adds the blank lines.
// The `lint` script in package.json chooses which directories are checked.
import stylistic from '@stylistic/eslint-plugin';

export default [
  {
    // The .js files are classic scripts: Safari loads them as extension and page scripts, and
    // the tests run them with `vm`. Parsing them as modules would reject valid sloppy-mode code.
    files: ['**/*.js'],
    languageOptions: { sourceType: 'script' }
  },
  {
    files: ['**/*.{js,mjs,cjs}'],
    plugins: { '@stylistic': stylistic },
    rules: {
      // The No Hands Stack reference block, unchanged.
      '@stylistic/padding-line-between-statements': [
        'error',
        { blankLine: 'always', prev: 'import', next: '*' },
        { blankLine: 'any', prev: 'import', next: 'import' },
        {
          blankLine: 'always',
          prev: '*',
          next: ['multiline-const', 'multiline-let', 'multiline-expression', 'block-like'],
        },
        {
          blankLine: 'always',
          prev: ['multiline-const', 'multiline-let', 'multiline-expression', 'block-like'],
          next: '*',
        },
        { blankLine: 'always', prev: '*', next: 'return' },
      ],
    }
  }
];
