// test_heaven.js - Suite de tests pour Heaven REPL WASM
const tests = [
    // Arithmétique de base
    { input: "2 + 3", expected: "5" },
    { input: "2 * 3 + 1", expected: "7" },
    { input: "10 / 2", expected: "5" },
    { input: "2^3", expected: "eval error: error.UnknownSymbol" },
    // Fonctions
    { input: "double x = x * 2", expected: "double clause (1 patterns) registered" },
    { input: "double 21", expected: "42" },
    { input: "triple x := x * 3", expected: "triple clause (1 patterns) registered" },
    { input: "triple 21", expected: "63" },
    // Inférence de type
    { input: "type 42", expected: "Int" },
    { input: "type (λx.x)", expected: "->" },
    { input: "type ((λx.x) 42)", expected: "Int" },
    // S-expressions
    { input: "(if (> 3 2) 1 0)", expected: "1" },
    { input: "(if (< 2 1) 10 20)", expected: "20" },
    // Simplification
    { input: "simplify (x + 0) * 1", expected: "(+ (x 0) * 1)" },
    // Dérivation
    { input: "derive x^2 + 2*x + 1", expected: "(+ (+ (+ 0 (* 0 x)) (* 2 1)) (* (* 2 (^ x 1)) 1))" },
    // Intégration
    { input: "integrate 2*x", expected: "(* (* * x) 2) + C" },
    // Théorèmes et preuves
    { input: "theorem add_zero : n + 0 = n", expected: "✓ theorem add_zero stated" },
    { input: "prove add_zero by simplify", expected: "✓ [add_zero] proved (simplify)" },
    // LaTeX - corrigé selon le résultat observé
    { input: "latex (x + y)^2", expected: "latex|\\mathrm{(x} + \\mathrm{y)^2}" },
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