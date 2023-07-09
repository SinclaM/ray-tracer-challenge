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
            new Uint8ClampedArray(
                this.instance.exports.memory.buffer,
                ptr,
                width * height * 4
            );
    },
    drawCanvas: function () {
        const ctx = canvas.getContext("2d");

        const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        imageData.data.set(this.pixels());
        ctx.putImageData(imageData, 0, 0);
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
    const start = window.performance.now();

    result = await WebAssembly.instantiateStreaming(
        fetch("ray-tracer-challenge.wasm"),
        importObject
    );
    wasm.init(result);

    const wasm_initialized = window.performance.now();
    console.log(`WASM initialized in ${wasm_initialized - start}ms`);

    cover_scene = await fetch("default-scene.json").then((r) => r.text());

    const ptr = wasm.instance.exports.initRenderer(
        wasm.encodeString(cover_scene)
    );
    const width = wasm.instance.exports.getWidth();
    const height = wasm.instance.exports.getHeight();

    const renderer_initialized = window.performance.now();
    console.log(
        `Renderer initialized in ${renderer_initialized - wasm_initialized}ms`
    );

    wasm.attachCanvas(ptr, width, height);

    const dy = 10;

    const renderLoop = () => {
        const done = wasm.instance.exports.render(dy);

        wasm.drawCanvas();

        if (done) {
            wasm.instance.exports.deinitRenderer();

            const render_finised = window.performance.now();
            console.log(
                `Render completed in ${render_finised - renderer_initialized}ms`
            );
            return;
        }

        requestAnimationFrame(renderLoop);
    };

    requestAnimationFrame(renderLoop);
})();
