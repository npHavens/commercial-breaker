// Blank-line rules only: no correctness or layout checks. `npm run lint -- --fix` adds the blank lines.
import stylistic from '@stylistic/eslint-plugin';

export default [
  // Only these directories are linted, however ESLint is started (`npm run lint`, `npx eslint .`
  // or an editor), so build output and cloned experiments are never checked or rewritten.
  { ignores: ['*', '!SafariExtension/', '!Tools/', '!Tests/'] },
  {
    // Classic scripts: Safari loads the extension's .js files as background, content and page
    // scripts, and the tests run them and the controller with `vm`. Node ESM files use .mjs.
    files: ['SafariExtension/**/*.js', 'Tools/commercial-controller.js'],
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
