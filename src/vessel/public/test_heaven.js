// test_heaven.js — Source unique: fetch /test_suite.hvn
// Remplace le tableau hardcodé de 64 tests par un parser dynamique
// aligné sur la logique de src/runtime/test_runner.zig

async function runTests(wasm) {
    const output = document.getElementById('output');
    const summaryEl = document.getElementById('summary');
    const t_start_total = performance.now();
    const mem_start = wasm.memory ? wasm.memory.buffer.byteLength : 0;
    let mem_peak = mem_start;

    let passed = 0, failed = 0, neutral = 0;

    const header = document.createElement('div');
    header.style.marginBottom = '10px';
    header.textContent = '── Running tests from test_suite.hvn (WASM) ──';
    output.appendChild(header);

    // Fetch the single source of truth
    let suiteText;
    try {
        const resp = await fetch('/test_suite.hvn');
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        suiteText = await resp.text();
    } catch (e) {
        output.appendChild(document.createTextNode(`✗ Failed to fetch test_suite.hvn: ${e}\n`));
        summaryEl.innerHTML = '<span style="color:#ff4444">✗ Cannot load test suite</span>';
        return;
    }

    const lines = suiteText.split('\n');
    for (const rawLine of lines) {
        const line = rawLine.trim();
        // Skip comments and empty lines (same as test_runner.zig lines 45-50)
        if (!line || line[0] === '#' || line.startsWith(';;') || line.startsWith('--') || line.startsWith('//')) continue;

        const t0 = performance.now();
        let result;
        try {
            result = wasm.heavenEval(line);
        } catch (e) {
            result = `error: ${e}`;
        }
        const t1 = performance.now();
        const wall_ms = t1 - t0;

        if (wasm.memory) {
            const m = wasm.memory.buffer.byteLength;
            if (m > mem_peak) mem_peak = m;
        }

        // Classify result (same logic as test_runner.zig lines 84-98)
        const hasFailMarker = result.includes('✗');
        const isPass = !hasFailMarker && (result.startsWith('✓') || result.includes(': ✓'));

        let icon, cls;
        if (hasFailMarker)      { icon = '✗'; cls = 'fail'; failed++; }
        else if (isPass)        { icon = '✓'; cls = 'pass'; passed++; }
        else                    { icon = '·'; cls = 'neutral'; neutral++; }

        const div = document.createElement('div');
        div.className = `test-result ${cls}`;
        div.appendChild(document.createTextNode(`${icon} `));
        const c1 = document.createElement('code'); c1.textContent = line; div.appendChild(c1);
        div.appendChild(document.createTextNode(' → '));
        const c2 = document.createElement('code'); c2.textContent = result; div.appendChild(c2);
        const timing = document.createElement('span');
        timing.style.cssText = 'color:#666;font-size:0.85em';
        timing.textContent = ` (${wall_ms.toFixed(2)}ms)`;
        div.appendChild(timing);
        output.appendChild(div);
    }

    const t_end_total = performance.now();
    const wall_total = t_end_total - t_start_total;
    const total = passed + failed;
    const n_meas = passed + failed + neutral;
    const avg = n_meas > 0 ? wall_total / n_meas : 0;

    let summary = `── Tests finished ──\n`;
    summary += `  ✓ ${passed} passed\n`;
    if (failed > 0) summary += `  ✗ ${failed} failed\n`;
    summary += `  ·  ${neutral} neutral\n`;
    summary += `  ─────────────\n`;
    summary += `  Total: ${passed} / ${total}\n\n`;
    summary += `  ── Performance ──\n`;
    summary += `  wall time:   ${wall_total.toFixed(2)} ms  (avg ${avg.toFixed(2)} ms / ligne)\n`;
    summary += `  peak mem:    ${(mem_peak / 1024).toFixed(0)} KB\n`;

    const perf = document.createElement('pre');
    perf.style.cssText = 'margin-top:20px;padding:10px;border:1px solid #00ff41;color:#00ff41;background:#000;';
    perf.textContent = summary;
    output.appendChild(perf);

    summaryEl.innerHTML = failed === 0
        ? `<span style="color:#00ff41">🎉 ${passed}/${total} tests passed (${neutral} neutral)</span>`
        : `<span style="color:#ff4444">⚠️ ${failed} échec(s) — ${passed}/${total} passed</span>`;
}

export { runTests };