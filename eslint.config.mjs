// Blank-line rules only: no correctness or layout checks. `npm run lint -- --fix` adds the blank lines.
import stylistic from '@stylistic/eslint-plugin';
import tseslint from 'typescript-eslint';

export default [
  // Only these directories are linted, however ESLint is started (`npm run lint`, `npx eslint .`
  // or an editor), so build output and cloned experiments are never checked or rewritten. The
  // extension's built scripts in SafariExtension/dist are output too.
  { ignores: ['*', '!SafariExtension/', '!Tools/', '!Tests/', 'SafariExtension/dist/'] },
  {
    // Classic scripts: Safari loads the extension's scripts as background, popup and page scripts,
    // and the tests run them with `vm`. Its TypeScript sources compile one-to-one to such scripts.
    // Node ESM files use .mjs.
    files: ['SafariExtension/**/*.js'],
    languageOptions: { sourceType: 'script' }
  },
  {
    files: ['SafariExtension/src/**/*.ts'],
    languageOptions: { parser: tseslint.parser, sourceType: 'script' }
  },
  {
    files: ['**/*.{js,mjs,cjs,ts}'],
    plugins: { '@stylistic': stylistic },
    rules: {
      // The No Hands Stack reference block, unchanged. CONTRIBUTING describes what it requires.
      // `multiline-type` and `interface` match only in the extension's TypeScript sources.
      '@stylistic/padding-line-between-statements': [
        'error',
        { blankLine: 'always', prev: 'import', next: '*' },
        { blankLine: 'any', prev: 'import', next: 'import' },
        {
          blankLine: 'always',
          prev: '*',
          next: [
            'multiline-const',
            'multiline-let',
            'multiline-expression',
            'multiline-block-like',
            'multiline-export',
            'multiline-type',
            'interface',
          ],
        },
        {
          blankLine: 'always',
          prev: [
            'multiline-const',
            'multiline-let',
            'multiline-expression',
            'multiline-block-like',
            'multiline-export',
            'multiline-type',
            'interface',
          ],
          next: '*',
        },
        { blankLine: 'always', prev: '*', next: 'return' },
      ],
    }
  }
];
