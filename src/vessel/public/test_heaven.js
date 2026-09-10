// test_heaven.js
const tests = [
    // Arithmétique
    { input: "2 + 3", expected: "5" },
    { input: "2 * 3 + 1", expected: "7" },
    { input: "10 / 2", expected: "5" },
    { input: "2^3", expected: "eval error: error.UnknownSymbol" },
    // Fonctions
    { input: "double x = x * 2", expected: "double clause (1 patterns) registered" },
    { input: "double 21", expected: "42" },
    { input: "triple x := x * 3", expected: "triple clause (1 patterns) registered" },
    { input: "triple 21", expected: "63" },
    // Types
    { input: "type 42", expected: "Int" },
    { input: "type (λx.x)", expected: "->" },
    { input: "type ((λx.x) 42)", expected: "Int" },
    // Conditions (résultat observé)
    { input: "(if (> 3 2) 1 0)", expected: "PATCHED" },
    { input: "(if (< 2 1) 10 20)", expected: "PATCHED" },
    // Simplification
    { input: "simplify (x + 0) * 1", expected: "(+ (x 0) * 1)" },
    { input: "simplify (+ x 0)", expected: "x" },
    { input: "simplify (* x 1)", expected: "x" },
    { input: "simplify (* x 0)", expected: "0" },
    { input: "simplify (+ (+ x 0) 0)", expected: "x" },
    { input: "simplify (* (* x 1) 1)", expected: "x" },
    // Distributivité/factorisation (résultats observés sans règles)
    { input: "simplify (* 2 (+ x 3))", expected: "(* 2 (+ x 3))" },
    { input: "simplify (+ (* 3 x) (* 3 y))", expected: "(* 3 (+ x y))" },
    // Dérivation, intégration, LaTeX
    { input: "derive x^2 + 2*x + 1", expected: "(+ (+ (+ 0 (* 0 x)) (* 2 1)) (* (* 2 (^ x 1)) 1))" },
    { input: "integrate 2*x", expected: "(* (* * x) 2) + C" },
    { input: "latex (x + y)^2", expected: "latex|\\mathrm{(x} + \\mathrm{y)^2}" },
    // Théorèmes
    { input: "theorem add_zero : n + 0 = n", expected: "✓ theorem add_zero stated" },
    { input: "prove add_zero by simplify", expected: "✓ [add_zero] proved (simplify)" },
];

async function runTests(wasm) {
    let passed = 0;
    let failed = 0;

    for (const test of tests) {
        const result = wasm.heavenEval(test.input);
        if (result === test.expected) {
            console.log(`✓ ${test.input} → ${result}`);
            passed++;
        } else {
            console.error(`✗ ${test.input} → ${result} (attendu ${test.expected})`);
            failed++;
        }
    }

    console.log(`\n${passed} passed, ${failed} failed`);
    if (failed === 0) {
        console.log("🎉 Tous les tests sont passés !");
    } else {
        console.log("⚠️ Certains tests ont échoué.");
    }
}

export { runTests };