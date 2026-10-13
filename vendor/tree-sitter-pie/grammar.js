module.exports = grammar({
  name: 'pie',

  extras: $ => [
    /\s/,
    $.comment
  ],

  rules: {
    source_file: $ => repeat($.expression),

    _definition: $ => $.expression,

    comment: $ => token(choice(
      seq(';', /.*/),
      seq('#|', /[^|]*\|+([^#|][^|]*\|+)*/, '#')
    )),

    expression: $ => choice(
      $.symbol,
      $.number,
      $.string,
      $.atom_literal,
      $.type_constructor,
      $.parenthesized_expr
    ),

    symbol: $ => /[a-zA-Z_+\-*\/!?<>=][a-zA-Z0-9_+\-*\/!?<>=]*/,

    number: $ => /\d+/,

    string: $ => /"([^"\\]|\\.)*"/,

    atom_literal: $ => seq("'", $.symbol),

    parenthesized_expr: $ => seq(
      '(',
      choice(
        // Top-level and expression forms
        seq('claim', field('name', $.symbol), field('type', $.expression)),
        seq('define', field('name', $.symbol), field('value', $.expression)),
        seq('check-same', field('type', $.expression), field('expr1', $.expression), field('expr2', $.expression)),
        seq('the', field('type', $.expression), field('value', $.expression)),
        seq(choice('lambda', 'λ'), '(', repeat(field('param', $.symbol)), ')', field('body', $.expression)),
        seq(choice('Pi', 'Π'), '(', '(', field('param', $.symbol), field('type', $.expression), ')', ')', field('return_type', $.expression)),
        seq(choice('Sigma', 'Σ'), '(', '(', field('param', $.symbol), field('type', $.expression), ')', ')', field('return_type', $.expression)),
        seq('->', repeat1(field('arg_type', $.expression)), field('return_type', $.expression)),
        seq('quote', field('value', $.expression)),
        // Built-in operations
        seq('car', field('pair', $.expression)),
        seq('cdr', field('pair', $.expression)),
        seq('cons', field('first', $.expression), field('second', $.expression)),
        seq('add1', field('nat', $.expression)),
        seq('which-Nat', field('target', $.expression), field('base', $.expression), field('step', $.expression)),
        seq('iter-Nat', field('target', $.expression), field('base', $.expression), field('step', $.expression)),
        seq('rec-Nat', field('target', $.expression), field('base', $.expression), field('step', $.expression)),
        seq('ind-Nat', field('target', $.expression), field('mot', $.expression), field('base', $.expression), field('step', $.expression)),
        seq('replace', field('target', $.expression), field('mot', $.expression), field('base', $.expression)),
        seq('trans', field('p1', $.expression), field('p2', $.expression)),
        seq('cong', field('p', $.expression), field('f', $.expression)),
        seq('symm', field('p', $.expression)),
        seq('ind-=', field('target', $.expression), field('mot', $.expression), field('base', $.expression)),
        seq('head', field('list', $.expression)),
        seq('tail', field('list', $.expression)),
        seq('rec-List', field('target', $.expression), field('base', $.expression), field('step', $.expression)),
        seq('ind-List', field('target', $.expression), field('mot', $.expression), field('base', $.expression), field('step', $.expression)),
        seq('vec-head', field('vec', $.expression)),
        seq('vec-tail', field('vec', $.expression)),
        seq('ind-Vec', field('len', $.expression), field('target', $.expression), field('mot', $.expression), field('base', $.expression), field('step', $.expression)),
        seq('ind-Either', field('target', $.expression), field('mot', $.expression), field('left', $.expression), field('right', $.expression)),
        seq('ind-Absurd', field('target', $.expression), field('mot', $.expression)),
        // General application (catch-all)
        seq(field('function', $.expression), repeat1(field('argument', $.expression)))
      ),
      ')'
    ),

    type_constructor: $ => choice(
      'Nat',
      'Atom',
      'Trivial',
      'Absurd',
      'List',
      'Vec',
      'Either',
      'Pair',
      '=',
      'U',
      'zero',
      'sole',
      'nil'
    )
  }
});
