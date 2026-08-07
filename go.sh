#rm -f .heaven_session.json ; rm -fr zig-out .zig-cache && zig build && zig build test && zig build wasm && cp zig-out/bin/heaven.wasm src/vessel/public/ && rlwrap -f <(./zig-out/bin/heaven --completions) ./zig-out/bin/heaven 8080

pkill -f "zig-out/bin/heaven" 2>/dev/null

rm -f .heaven_session.json ; rm -fr zig-out .zig-cache && \
zig build && \
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall -p zig-out/wasm && \
cp zig-out/wasm/bin/heaven.wasm src/vessel/public/ && \
zig build test && \
rlwrap -f <(./zig-out/bin/heaven --completions) ./zig-out/bin/heaven 8080
