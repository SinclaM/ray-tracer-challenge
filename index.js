// ============================== DOM ELEMENTS =================================
const canvas = document.getElementById("image-canvas");
const textarea = document.getElementById("scene-description");
const render_button = document.getElementById("render");
const editor = ace.edit("scene-description");
const sceneChoices = document.getElementById("scene-choices");
const split = document.querySelector(".split");
const split0 = document.getElementById("split-0");
const split1 = document.getElementById("split-1");
// =============================================================================

// ============================ UI INITIALIZATION ==============================
const initSplit = () => {
    document.querySelectorAll(".gutter").forEach((gutter) => gutter.remove());

    if (window.innerWidth > window.innerHeight) {
        // Use a horizontal split on screens more long than wide.
        Split(["#split-0", "#split-1"]);

        split.style["grid-row"] = "2";
        split.style["height"] = "90vh";
        split.style["display"] = "flex";
        split.style["flex-direction"] = "row";

        split0.style["height"] = "100%";
        split1.style["height"] = "100%";
    } else {
        // Otherwise, use a vertical split.
        Split(["#split-0", "#split-1"], {
            direction: "vertical",
        });
        split.style["grid-row"] = "";
        split.style["height"] = "";
        split.style["display"] = "";
        split.style["flex-direction"] = "";

        split0.style["width"] = "100%";
        split1.style["width"] = "100%";
    }
};

initSplit();
window.addEventListener("resize", initSplit);

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
// =============================================================================

// ============================= WASM INTERACTIONS =============================
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
    drawCanvas: function (current_y, dy) {
        const start = current_y * canvas.width * 4;
        const end = (current_y + dy) * canvas.width * 4;

        const height = Math.min(dy, canvas.height - current_y);
        const imageData = new ImageData(this.pixels().slice(start, end), canvas.width, height);

        const ctx = canvas.getContext("2d");
        ctx.putImageData(imageData, 0, current_y);
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
        loadObjData: function (name_ptr, name_len) {
            name_ = wasm.getString(name_ptr, Number(name_len));
            return wasm.encodeString(obj_names_to_data.get(name_));
        }
    },
};
// =============================================================================

// ============================== RENDER LOGIC =================================
let rendering = false;

const render = () => {
    rendering = true;

    // Log the current mem usage for debugging
    mem = (function formatBytes(bytes, decimals = 2) {
        if (!+bytes) return '0 Bytes'

        const k = 1024
        const dm = decimals < 0 ? 0 : decimals
        const sizes = ['Bytes', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB', 'ZiB', 'YiB']

        const i = Math.floor(Math.log(bytes) / Math.log(k))

        return `${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} ${sizes[i]}`
    })(wasm.instance.exports.memory.buffer.byteLength, 5);
    console.log(`WASM memory size: ${mem}.`);

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

    let current_y = 0;
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
        wasm.drawCanvas(current_y, dy);
        current_y += dy;

        // If there are no more rows left to render, we can clean up and exit.
        if (done) {
            // Make sure to destroy the renderer if exiting on success.
            wasm.instance.exports.deinitRenderer();

            const render_finised = window.performance.now();
            console.log(
                `Render completed in ${
                    render_finised - renderer_initialized
                }ms.`
            );

            notyf.success(
                `Render finished in ${(
                    (render_finised - renderer_initialized) /
                    1000
                ).toFixed(3)}s.`
            );

            rendering = false;

            return;
        }

        // Otherwise, continue with the next batch of rows.
        requestAnimationFrame(renderLoop);
    };

    requestAnimationFrame(renderLoop);
};
// =============================================================================

// ======================= WASM/REMAINING UI INITIALIZATION ====================
const obj_names_to_data = new Map();
(async () => {
    obj_names_to_data.set("teapot.obj", await fetch("teapot.obj").then((r) => r.text()));
    obj_names_to_data.set("dragon.obj", await fetch("dragon.obj").then((r) => r.text()));

    const start = window.performance.now();

    result = await WebAssembly.instantiateStreaming(
        fetch("ray-tracer-challenge.wasm"),
        importObject
    );
    wasm.init(result);

    const wasm_initialized = window.performance.now();
    console.log(`WASM initialized in ${wasm_initialized - start}ms.`);

    const default_scene = await fetch(
        sceneChoices.children[0].children[0].getAttribute("value")
    ).then(
        (r) => r.text()
    );

    editor.setValue(default_scene);
    editor.clearSelection();
    editor.session.getUndoManager().reset();

    textarea.value = default_scene;

    render_button.addEventListener("click", (_) => {
        // FIXME: probably a TOCTOU race here.
        if (!rendering) {
            render();
        }
    });

    // Add a hotkey for rendering
    document.addEventListener("keydown", (event) => {
        if ((event.ctrlKey || event.metaKey) && event.key === ".") {
            render_button.click();
        }
    });

    render_button.click();
})();
// =============================================================================
