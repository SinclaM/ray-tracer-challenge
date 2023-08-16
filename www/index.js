import * as Comlink from "./comlink.mjs";
// ============================== DOM ELEMENTS =================================
const canvas = document.getElementById("image-canvas");
const textarea = document.getElementById("scene-description");
const render_button = document.getElementById("render");
const add_obj_input = document.getElementById("add-obj");
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
const user_added_objs = new Map();
add_obj_input.addEventListener("change", async () => {
    const [file] = add_obj_input.files;
    user_added_objs.set(file.name, await file.text());
    notyf.success(`Added ${file.name}`);
});

const drawCanvas = (y0, dy, pixels) => {
    const height = Math.min(dy, canvas.height - y0);
    const imageData = new ImageData(pixels, canvas.width, height);

    const ctx = canvas.getContext("2d");
    ctx.putImageData(imageData, 0, y0);
}

let rendering = false;

const render = async () => {
    rendering = true;

    const render_start = window.performance.now();

    // We will render in batches of `dy` rows.
    const dy = 10;

    const scene = editor.getValue();

    let width = undefined;
    let height = undefined;
    try {
        const dims = (await Promise.all(workers.map((obj, id) => obj.init(id, scene, user_added_objs, dy))))[0];
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

    let jobs = [];
    for (let y0 = 0; y0 < height; y0 += dy) {
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

    await Promise.all(workers.map((obj) => obj.deinit()));

    const render_finised = window.performance.now();

    const message = `Render finished in ${((render_finised - render_start) / 1000).toFixed(3)}s.`;

    console.log(message);
    notyf.success(message);

    rendering = false;
};
// =============================================================================

// ======================= WASM/REMAINING UI INITIALIZATION ====================
(async () => {
    const default_scene = await fetch(
        `scenes/${sceneChoices.children[0].children[0].getAttribute("value")}`
    ).then(
        (r) => r.text()
    );

    editor.setValue(default_scene);
    editor.clearSelection();
    editor.session.getUndoManager().reset();

    textarea.value = default_scene;

    render_button.addEventListener("click", async (_) => {
        // FIXME: probably a TOCTOU race here.
        if (!rendering) {
            await render();
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
