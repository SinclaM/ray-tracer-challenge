// ============================== DOM ELEMENTS =================================
const canvas = document.getElementById("image-canvas");
const textarea = document.getElementById("scene-description");
const renderButton = document.getElementById("render");
const addFileInput = document.getElementById("add-file");
const editor = ace.edit("scene-description");
const sceneChoices = document.getElementById("scene-choices");
const split = document.querySelector(".split");
const split0 = document.getElementById("split-0");
const split1 = document.getElementById("split-1");
const upArrow = document.querySelector(".arrow-key.up");
const downArrow = document.querySelector(".arrow-key.down");
const leftArrow = document.querySelector(".arrow-key.left");
const rightArrow = document.querySelector(".arrow-key.right");
// =============================================================================

// ============================ UI INITIALIZATION ==============================
const initSplit = () => {
    document.querySelectorAll(".gutter").forEach((gutter) => gutter.remove());

    if (window.innerWidth > window.innerHeight) {
        // Use a horizontal split on screens more long than wide.
        Split(["#split-0", "#split-1"], { minSize: [100, 300] });

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
            minSize: [100, 200]
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
let notyf = new Notyf({ position: { x: "left", y: "bottom" } });

// Set up scene description editor
editor.setOption("showLineNumbers", false);
editor.setOption("fontSize", "13pt");
editor.setOption("fontFamily", "JetBrains Mono, monospace");
editor.setShowPrintMargin(false);
editor.setTheme("ace/theme/dawn");
editor.session.setMode("ace/mode/json");

sceneChoices.addEventListener("change", async (event) => {
    editor.setValue(await fetch(`scenes/${event.target.value}`).then((r) => r.text()));
    editor.clearSelection();
});
// =============================================================================
// ================================= WORKERS ===================================
const exports = {
    startInitRenderer: Module.cwrap("startInitRenderer", null, ["string", "number"]),
    tryFinishInitRenderer: Module.cwrap("tryFinishInitRenderer", "number", []),
    initRendererIsOk: Module.cwrap("initRendererIsOk", "number", []),
    initRendererGetPixels: Module.cwrap("initRendererGetPixels", "number", []),
    initRendererGetWidth: Module.cwrap("initRendererGetWidth", "number", []),
    initRendererGetHeight: Module.cwrap("initRendererGetHeight", "number", []),
    initRendererGetErr: Module.cwrap("initRendererGetErr", "string", []),
    startRender: Module.cwrap("startRender", null, []),
    tryFinishRender: Module.cwrap("tryFinishRender", "number", []),
    rotateCamera: Module.cwrap("rotateCamera", null, ["number"]),
    moveCamera: Module.cwrap("moveCamera", null, ["number"]),
    deinitRenderer: Module.cwrap("deinitRenderer", null, []),
};

const waitForCondition = (condition, pollInterval, action) => {
    const waitFor = (result) => {
        if (result) {
            return result;
        }
        return new Promise((resolve) => setTimeout(resolve, pollInterval))
            .then(() => Promise.resolve(condition()))
            .then((res) => {
                action();
                return waitFor(res);
            });
    }

    return waitFor();
}

const renderInterface = {
    pixels: undefined,

    init: async function(scene) {
        // Tell the WASM code to initialize the renderer.
        exports.startInitRenderer(scene, navigator.hardwareConcurrency);

        // Dumb heuristic. Scenes referencing files (meshes, texture maps)
        // are likely to take longer to initialize.
        const initPollInterval = scene.includes("\"file\"") ? 100 : 10;

        await waitForCondition(exports.tryFinishInitRenderer, initPollInterval, () => {});

        // If there was an error, bail out.
        if (!exports.initRendererIsOk()) {
            const errorName = exports.initRendererGetErr();
            throw new Error(errorName);
        } else {
            const pixelsPtr = exports.initRendererGetPixels();
            const width = exports.initRendererGetWidth();
            const height = exports.initRendererGetHeight();

            // Must use wasmMemory.buffer instead of Module.HEAPU8.buffer.
            // Even though the emscripten docs say that canonical views like HEAPU8
            // are refreshed when memory grows, this does not seem to actually be
            // true.
            this.pixels = () => new Uint8ClampedArray(
                wasmMemory.buffer,
                pixelsPtr,
                width * height * 4
            );

            return { width, height };
        }
    },
    render: async function() {
        exports.startRender();

        await waitForCondition(
            exports.tryFinishRender,
            100,
            () => drawCanvas(0, canvas.height, renderInterface.pixels)
        );
    },
    rotateCamera: exports.rotateCamera,
    moveCamera: exports.moveCamera,
    deinit: exports.deinitRenderer,
};
// =============================================================================
// ============================== RENDER LOGIC =================================
addFileInput.addEventListener("change", async () => {
    const [file] = addFileInput.files;

    const fr = new FileReader();
    fr.onload = () => {
        const data = new Uint8Array(fr.result);
        Module["FS_createDataFile"]("/", file.name, data, true, true, true);
    };

    fr.readAsArrayBuffer(file);

    notyf.success(`Added ${file.name}`);
});

const drawCanvas = (y0, dy, pixels) => {
    const height = Math.min(dy, canvas.height - y0);
    const imageData = new ImageData(pixels().slice(), canvas.width, height);

    const ctx = canvas.getContext("2d");
    ctx.putImageData(imageData, 0, y0);
};

let rendering = false;
let rendererIsInitialized = false;

const render = async (skipInitDeinit, silentOnSuccess) => {
    rendering = true;

    const renderStart = window.performance.now();

    if (rendererIsInitialized && !skipInitDeinit) {
        renderInterface.deinit();
        rendererIsInitialized = false;
    }

    if (!skipInitDeinit) {
        const scene = editor.getValue();

        let width = undefined;
        let height = undefined;
        try {
            const dims = await renderInterface.init(scene);
            rendererIsInitialized = true;
            width = dims.width;
            height = dims.height;
        } catch (error) {
            console.error(error);
            notyf.error(`Unable to initialize renderer: ${error.message}.`);
            rendering = false;
            return;
        }

        canvas.width = width;
        canvas.height = height;
    }

    await renderInterface.render();
    const renderFinised = window.performance.now();

    if (!silentOnSuccess) {
        const message = `Render finished in ${((renderFinised - renderStart) / 1000).toFixed(3)}s.`;
        console.log(message);
        notyf.success(message);
    }

    rendering = false;
};
// =============================================================================
// ======================= WASM/REMAINING UI INITIALIZATION ====================
(async () => {
    const defaultScene = await fetch(
        `scenes/${sceneChoices.children[0].children[0].getAttribute("value")}`
    ).then(
        (r) => r.text()
    );

    editor.setValue(defaultScene);
    editor.clearSelection();
    editor.session.getUndoManager().reset();

    textarea.value = defaultScene;

    renderButton.addEventListener("click", async (_) => {
        // FIXME: probably a TOCTOU race here.
        if (!rendering) {
            await render(false, false);
        }
    });

    // Add a hotkey for rendering
    document.addEventListener("keydown", (event) => {
        if ((event.ctrlKey || event.metaKey) && event.key === ".") {
            renderButton.click();
        }
    });

    Module["onRuntimeInitialized"] = () => {
        renderButton.click();
    };
})();
// =============================================================================
// ========================== ARROW KEYS INTERACTIVITY =========================
let handlingMove = false

const rotateCamera = async (angle, keyElement) => {
    if (!handlingMove && !rendering) {
        handlingMove = true;
        keyElement.classList.add("press");
        renderInterface.rotateCamera(angle);
        await render(true, true);
        keyElement.classList.remove("press");
        handlingMove = false;
    }
};

const moveCamera = async (distance, keyElement) => {
    if (!handlingMove && !rendering) {
        handlingMove = true;
        keyElement.classList.add("press");
        renderInterface.moveCamera(distance);
        await render(true, true);
        keyElement.classList.remove("press");
        handlingMove = false;
    }
};

upArrow.addEventListener("click", (_) => moveCamera(0.1, upArrow));
downArrow.addEventListener("click", (_) => moveCamera(-0.1, downArrow));
leftArrow.addEventListener("click", (_) => rotateCamera(Math.PI / 30.0, leftArrow));
rightArrow.addEventListener("click", (_) => rotateCamera(-Math.PI / 30.0, rightArrow));

window.addEventListener(
    "keydown",
    (event) => {
        if (event.defaultPrevented || editor.isFocused()) {
            return; // Do nothing if the event was already processed
        }

        switch (event.key) {
            case "ArrowDown":
                moveCamera(-1 / 9, downArrow);
                break;
            case "ArrowUp":
                moveCamera(1 / 10, upArrow);
                break;
            case "ArrowLeft":
                rotateCamera(Math.PI / 30.0, leftArrow);
                break;
            case "ArrowRight":
                rotateCamera(-Math.PI / 30.0, rightArrow);
                break;
            default:
                return; // Quit when this doesn't handle the key event.
        }

        // Cancel the default action to avoid it being handled twice
        event.preventDefault();
    },
    true,
);
 //=============================================================================
