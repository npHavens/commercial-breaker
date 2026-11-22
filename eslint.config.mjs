// Blank-line rules only: no correctness or layout checks. `npm run lint -- --fix` adds the blank lines.
import stylistic from '@stylistic/eslint-plugin';

export default [
  {
    files: ['SafariExtension/**/*.js', 'Tools/**/*.{js,mjs}', 'Tests/**/*.{js,mjs,cjs}'],
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
