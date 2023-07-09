const canvas = document.getElementById("image-canvas");

const clamp = (val) =>
    val * 255.0 > 255.0 ? 255 : val * 255.0 < 0.0 ? 0 : val * 255.0;

const text_decoder = new TextDecoder();
let console_log_buffer = "";

let wasm = {
    instance: undefined,
    pixels: undefined,

    init: function (obj) {
        this.instance = obj.instance;
    },
    getString: function (ptr, len) {
        const memory = this.instance.exports.memory;
        return text_decoder.decode(new Uint8Array(memory.buffer, ptr, len));
    },
    attachCanvas: function (ptr, width, height) {
        canvas.width = width;
        canvas.height = height;

        this.pixels = () =>
            new Float64Array(
                this.instance.exports.memory.buffer,
                ptr,
                width * height * 3
            );
    },
    drawCanvas: function (current_y, dy) {
        const ctx = canvas.getContext("2d");

        const pixels = this.pixels();

        for (
            let y = current_y;
            y < Math.max(current_y + dy, canvas.height);
            y++
        ) {
            for (let x = 0; x < canvas.width; x++) {
                const i = y * canvas.width + x;
                const [r, g, b] = pixels
                    .slice(i * 3, i * 3 + 3)
                    .map((v) => clamp(v));

                ctx.fillStyle = "rgba(" + r + ", " + g + ", " + b + ", 255)";
                ctx.fillRect(x, y, 1, 1);
            }
        }
    },
    // Convert a JavaScript string to a pointer to multi byte character array
    encodeString: function (string) {
        const buffer = new TextEncoder().encode(string);
        const pointer = this.instance.exports.wasmAlloc(buffer.length + 1); // ask Zig to allocate memory
        const slice = new Uint8Array(
            this.instance.exports.memory.buffer, // memory exported from Zig
            pointer,
            buffer.length + 1
        );
        slice.set(buffer);
        slice[buffer.length] = 0; // null byte to null-terminate the string
        return pointer;
    },
};

const importObject = {
    env: {
        jsConsoleLogWrite: function (ptr, len) {
            console_log_buffer += wasm.getString(ptr, len);
        },
        jsConsoleLogFlush: function () {
            console.log(console_log_buffer);
            console_log_buffer = "";
        },
    },
};

(async () => {
    result = await WebAssembly.instantiateStreaming(
        fetch("ray-tracer-challenge.wasm"),
        importObject
    );
    wasm.init(result);

    cover_scene = await fetch("cover.json").then((r) => r.text());

    const ptr = wasm.instance.exports.initRenderer(wasm.encodeString(cover_scene));
    const width = wasm.instance.exports.getWidth();
    const height = wasm.instance.exports.getHeight();

    wasm.attachCanvas(ptr, width, height);

    let current_y = 0;
    const dy = 50;

    const renderLoop = () => {
        const done = wasm.instance.exports.render(dy);

        wasm.drawCanvas(current_y, dy);
        current_y += dy;

        if (done) {
            wasm.instance.exports.deinitRenderer();
            return;
        }

        requestAnimationFrame(renderLoop);
    };

    requestAnimationFrame(renderLoop);
})();
