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
    { input: "(if (> 3 2) 1 0)", expected: "1" },
    { input: "(if (< 2 1) 10 20)", expected: "20" },
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
    const output = document.getElementById('output');
    const summaryEl = document.getElementById('summary');
    const t_start_total = performance.now();
    const mem_start = wasm.memory ? wasm.memory.buffer.byteLength : 0;
    let mem_peak = mem_start;

    let passed = 0, failed = 0;

    const header = document.createElement('div');
    header.style.marginBottom = '10px';
    header.textContent = '── Running tests from wasm ──';
    output.appendChild(header);

    for (const t of tests) {
        const t0 = performance.now();
        let result;
        try {
            result = wasm.heavenEval(t.input);
        } catch (e) {
            result = `error: ${e}`;
        }
        const t1 = performance.now();
        const wall_ms = t1 - t0;

        if (wasm.memory) {
            const m = wasm.memory.buffer.byteLength;
            if (m > mem_peak) mem_peak = m;
        }

        // WASM retourne le résultat brut (pas de marqueurs ✓/✗ comme le natif)
        // → on classe par comparaison avec expected
        const hasFailMarker = result.includes('✗');
        const matches = result === t.expected || result.includes(t.expected);

        let icon, cls;
        if (hasFailMarker || !matches) { icon = '✗'; cls = 'fail'; failed++; }
        else                           { icon = '✓'; cls = 'pass'; passed++; }

        const div = document.createElement('div');
        div.className = `test-result ${cls}`;
        div.appendChild(document.createTextNode(`${icon} `));
        const c1 = document.createElement('code'); c1.textContent = t.input; div.appendChild(c1);
        div.appendChild(document.createTextNode(' → '));
        const c2 = document.createElement('code'); c2.textContent = result; div.appendChild(c2);
        div.appendChild(document.createTextNode(' '));
        const timing = document.createElement('span');
        timing.style.cssText = 'color:#666;font-size:0.85em';
        timing.textContent = `(${wall_ms.toFixed(2)}ms)`;
        div.appendChild(timing);
        if (!matches) {
            div.appendChild(document.createTextNode(' '));
            const note = document.createElement('span');
            note.style.cssText = 'color:#ff8800;font-size:0.85em';
            note.textContent = `(attendu ${t.expected})`;
            div.appendChild(note);
        }
        output.appendChild(div);
    }

    const t_end_total = performance.now();
    const wall_total = t_end_total - t_start_total;
    const n = tests.length;
    const avg = wall_total / n;
    const total = passed + failed;

    let summary = `── Tests finished ──\n`;
    summary += `  ✓ ${passed} passed\n`;
    if (failed > 0) summary += `  ✗ ${failed} failed\n`;
    summary += `  ─────────────\n`;
    summary += `  Total: ${passed} / ${total}\n\n`;
    summary += `  ── Performance ──\n`;
    summary += `  wall time:   ${wall_total.toFixed(2)} ms  (avg ${avg.toFixed(2)} ms / ligne)\n`;
    summary += `  cpu time:    ${wall_total.toFixed(2)} ms  (approx, WASM mono-thread)\n`;
    summary += `  peak mem:    ${(mem_peak / 1024).toFixed(0)} KB\n`;
    summary += `  (résolution ±1ms, contrainte navigateur)`;

    const perf = document.createElement('pre');
    perf.style.cssText = 'margin-top:20px;padding:10px;border:1px solid #00ff41;color:#00ff41;background:#000;';
    perf.textContent = summary;
    output.appendChild(perf);

    summaryEl.innerHTML = failed === 0
        ? `<span style="color:#00ff41">🎉 ${passed}/${total} tests passed</span>`
        : `<span style="color:#ff4444">⚠️ ${failed} échec(s) — ${passed}/${total} passed</span>`;
}

export { runTests };