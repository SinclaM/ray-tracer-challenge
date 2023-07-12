const canvas = document.getElementById("image-canvas");
const textarea = document.getElementById("scene-description");
const render_button = document.getElementById("render");
const editor = ace.edit("scene-description");
const sceneChoices = document.getElementById("scene-choices");

// Set up resizable split between editor and scene
Split(["#split-0", "#split-1"]);

// Set up Notyf
let notyf = new Notyf();

// Set up scene description editor
editor.setOption("showLineNumbers", false);
editor.setOption("fontSize", "13pt");
editor.setOption("fontFamily", "JetBrains Mono, monospace");
editor.setShowPrintMargin(false);
editor.setTheme("ace/theme/dawn");
editor.session.setMode("ace/mode/json");

sceneChoices.addEventListener("change", async (event) => {
    editor.setValue(await fetch(event.target.value).then((r) => r.text()));
    editor.clearSelection();
});

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

let rendering = false;

const render = () => {
    rendering = true;

    scene = editor.getValue();

    // Tell the WASM code to initialize the renderer.
    wasm.instance.exports.initRenderer(wasm.encodeString(scene));

    // If there was an error, bail out.
    if (!wasm.instance.exports.initRendererIsOk()) {
        const error_ptr = wasm.instance.exports.initRendererGetErrPtr();
        const error_len = wasm.instance.exports.initRendererGetErrLen();

        const error_message = wasm.getString(error_ptr, error_len);
        console.error(`Unable to initialize renderer: ${error_message}.`);
        notyf.error(`Unable to initialize renderer: ${error_message}.`);

        rendering = false;
        return;
    }

    // Get the Canvas information and update the UI.
    const ptr = wasm.instance.exports.initRendererGetPixels();
    const width = wasm.instance.exports.initRendererGetWidth();
    const height = wasm.instance.exports.initRendererGetHeight();

    const renderer_initialized = window.performance.now();

    wasm.attachCanvas(ptr, width, height);

    // We will render in batches of `dy` rows.
    const dy = 10;

    const renderLoop = () => {
        // Render `dy` more rows of the scene.
        wasm.instance.exports.render(dy);

        // If there was an error, bail out.
        if (!wasm.instance.exports.renderIsOk()) {
            // Make sure to destroy the renderer if exiting on failure.
            wasm.instance.exports.deinitRenderer();

            const error_ptr = wasm.instance.exports.renderGetErrPtr();
            const error_len = wasm.instance.exports.renderGetErrLen();

            const error_message = wasm.getString(error_ptr, error_len);
            console.error(`Unable to render: ${error_message}.`);
            notyf.error(`Unable to render: ${error_message}.`);

            rendering = false;
            return;
        }

        const done = wasm.instance.exports.renderGetStatus();

        // Update the UI.
        wasm.drawCanvas();

        // If there are no more rows left to render, we can clean up and exit.
        if (done) {
            // Make sure to destroy the renderer if exiting on success.
            wasm.instance.exports.deinitRenderer();

            const render_finised = window.performance.now();
            console.log(
                `Render completed in ${render_finised - renderer_initialized}ms.`
            );

            notyf.success(`Render finished in ${render_finised - renderer_initialized}ms.`);

            rendering = false;

            return;
        }

        // Otherwise, continue with the next batch of rows.
        requestAnimationFrame(renderLoop);
    };

    requestAnimationFrame(renderLoop);
}

(async () => {
    const start = window.performance.now();

    result = await WebAssembly.instantiateStreaming(
        fetch("ray-tracer-challenge.wasm"),
        importObject
    );
    wasm.init(result);

    const wasm_initialized = window.performance.now();
    console.log(`WASM initialized in ${wasm_initialized - start}ms`);

    cover_scene = await fetch("cover.json").then((r) => r.text());

    editor.setValue(cover_scene);
    editor.clearSelection();

    textarea.value = cover_scene;

    render_button.addEventListener("click", (_) => {
        // FIXME: probably a TOCTOU race here.
        if (!rendering) {
            render();
        }
    });

    render();
})();
