export class HeavenHost {
    constructor() {
        this.wasm = null;
        this.memory = null;
        this.ws = null;
        this.peers = new Map(); // peer_id -> RTCDataChannel
    }

    async init(wasmPath) {
        const debugChannel = new BroadcastChannel('heaven-debug');
        const imports = {
            env: {
                js_console_log: (ptr, len) => {
                    const text = readStringFromWasm(ptr, len);
                    console.log(text);
                    // Envoie le log directement au debugger-frame.html via le BroadcastChannel
                    debugChannel.postMessage({ text, level: 'info' });
                    },
                js_console_error: (ptr, len) => console.error(this.readString(ptr, len)),
                js_websocket_connect: (ptr, len) => this.connectWebSocket(this.readString(ptr, len)),
                js_websocket_send: (ptr, len) => this.ws?.send(this.readString(ptr, len)),
                js_performance_now: () => performance.now(),
            }
        };

        const { instance } = await WebAssembly.instantiateStreaming(fetch(wasmPath), imports);
        this.wasm = instance.exports;
        this.memory = instance.exports.memory;
    }

    // --- REPL / IO ---
    sendReplInput(text) {
        const bytes = new TextEncoder().encode(text);
        const ptr = this.wasm.alloc(bytes.length); // Alloue dans le tas WASM
        new Uint8Array(this.memory.buffer, ptr, bytes.length).set(bytes);
        this.wasm.wasm_inject_repl_input(ptr, bytes.length);
        this.wasm.free(ptr, bytes.length);
    }

    // --- Helpers Mémoire ---
    readString(ptr, len) {
        const bytes = new Uint8Array(this.memory.buffer, ptr, len);
        return new TextDecoder().decode(bytes);
    }

    connectWebSocket(url) {
        this.ws = new WebSocket(url);
        this.ws.onmessage = (evt) => {
            // Transfert des paquets réseau entrants vers la MessageQueue WASM
        };
    }
}
