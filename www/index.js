import * as Comlink from "./comlink.mjs";
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
const NUM_WORKERS = navigator.hardwareConcurrency;

const workers = [];
for (let i = 0; i < NUM_WORKERS; i++) {
    const worker = new Worker("worker.js");
    const obj = Comlink.wrap(worker);
    workers.push(obj);
}

// =============================================================================
// ============================== RENDER LOGIC =================================
const userAddedFiles = new Map();
addFileInput.addEventListener("change", async () => {
    const [file] = addFileInput.files;
    userAddedFiles.set(file.name, await file.text());
    notyf.success(`Added ${file.name}`);
});

const drawCanvas = (y0, dy, pixels) => {
    const height = Math.min(dy, canvas.height - y0);
    console.log(pixels, canvas.width, height);
    const imageData = new ImageData(pixels, canvas.width, height);

    const ctx = canvas.getContext("2d");
    ctx.putImageData(imageData, 0, y0);
}

let rendering = false;
let rendererIsInitialized = false;

const render = async (skipInitDeinit, silentOnSuccess) => {
    rendering = true;

    const renderStart = window.performance.now();

    if (rendererIsInitialized && !skipInitDeinit) {
        await Promise.all(workers.map((obj) => obj.deinit()));
        rendererIsInitialized = false;
    }

    // We will render in batches of `dy` rows.
    const dy = 10;

    if (!skipInitDeinit) {
        const scene = editor.getValue();

        let width = undefined;
        let height = undefined;
        try {
            const dims = (await Promise.all(workers.map((obj, id) => obj.init(id, scene, userAddedFiles, dy))))[0];
            rendererIsInitialized = true;
            width = dims.width;
            height = dims.height;
        } catch (error) {
            console.error(`Unable to initialize renderer: ${error.message}.`)
            notyf.error(`Unable to initialize renderer: ${error.message}.`);
            rendering = false;
            return;
        }

        canvas.width = width;
        canvas.height = height;
    }

    let jobs = [];
    for (let y0 = 0; y0 < canvas.height; y0 += dy) {
        jobs.push({ y0, dy });
    }

    // Shuffle the batching order to make the image "fade-in" (kind of)
    // rather than simply rendering top-down or bottom-up.
    //
    // There's not much reason for this particular order, I just think it
    // looks nice.
    const m = 6 * dy;
    const n = 3;
    jobs.sort((a, b) => (a.y0 % m) - (b.y0 % m) + ((a.y0 + b.y0) % n));
    jobs = jobs.reverse();

    async function helper(obj) {
        return new Promise(async (resolve) => {
            const job = jobs.pop();
            if (typeof(job) != "undefined") {
                const pixels = await obj.render(job.y0);
                drawCanvas(job.y0, job.dy, pixels);
                await helper(obj);
            }
            resolve();
        });
    }
    await Promise.all(workers.map((obj) => helper(obj)));

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

    renderButton.click();
})();
// =============================================================================
// ========================== ARROW KEYS INTERACTIVITY =========================
let handlingMove = false

const rotateCamera = async (angle, keyElement) => {
    if (!handlingMove && !rendering) {
        handlingMove = true;
        keyElement.classList.add("press");
        await Promise.all(workers.map((obj) => obj.rotateCamera(angle)));
        await render(true, true);
        keyElement.classList.remove("press");
        handlingMove = false;
    }
};

const moveCamera = async (distance, keyElement) => {
    if (!handlingMove && !rendering) {
        handlingMove = true;
        keyElement.classList.add("press");
        await Promise.all(workers.map((obj) => obj.moveCamera(distance)));
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
// =============================================================================
