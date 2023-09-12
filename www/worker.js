importScripts("./comlink.js");

const textDecoder = new TextDecoder();
let consoleLogBuffer = "";
let wasm = undefined;
let userAddedObjs = undefined;

const obj = {
    id: undefined,
    dy: undefined,
    width: undefined,
    height: undefined,
    pixels: undefined,
    userAddedObjs: undefined,

    init: async function(id, scene, objs, dy) {
        this.id = id;
        this.dy = dy;
        userAddedObjs = objs;
        if (typeof(wasm) == "undefined") {
            wasm = {
                instance: undefined,
                pixels: undefined,

                init: function (instance) {
                    this.instance = instance;
                },
                getString: function (ptr, len) {
                    const view = new Uint8Array(this.instance.exports.memory.buffer, ptr, len);
                    return textDecoder.decode(view);
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
                    _throwError(pointer, length) {
                        const message = wasm.getString(pointer, length);
                        throw new Error(message);
                    },
                    jsConsoleLogWrite: function (ptr, len) {
                        consoleLogBuffer += wasm.getString(ptr, len);
                    },
                    jsConsoleLogFlush: function () {
                        console.log(`[Worker ${id}] ${consoleLogBuffer}`);
                        consoleLogBuffer = "";
                    },
                    loadFileData: function (namePtr, nameLen) {
                        name_ = wasm.getString(namePtr, Number(nameLen));

                        const data = userAddedObjs.get(name_);
                        if (typeof(data) != "undefined") {
                            return wasm.encodeString(data);
                        }

                        const request = new XMLHttpRequest();
                        request.open("GET", `data/${name_}`, false);
                        request.send(null);

                        return wasm.encodeString(request.responseText);
                    }
                },
            };

            await WebAssembly.instantiateStreaming(fetch("ray-tracer-challenge.wasm"), importObject).then(
                (obj) => wasm.init(obj.instance),
            );
        }

        // Tell the WASM code to initialize the renderer.
        wasm.instance.exports.initRenderer(wasm.encodeString(scene), this.dy);

        // If there was an error, bail out.
        if (!wasm.instance.exports.initRendererIsOk()) {
            const errorPtr = wasm.instance.exports.initRendererGetErrPtr();
            const errorLen = wasm.instance.exports.initRendererGetErrLen();

            const errorMessage = wasm.getString(errorPtr, errorLen);
            throw new Error(errorMessage);
        } else {
            const pixelsPtr = wasm.instance.exports.initRendererGetPixels();
            this.width = wasm.instance.exports.initRendererGetWidth();
            this.height = wasm.instance.exports.initRendererGetHeight();

            this.pixels = () => new Uint8ClampedArray(
                wasm.instance.exports.memory.buffer,
                pixelsPtr,
                this.width * this.dy * 4
            );

            return { width: this.width, height: this.height };
        }
    },
    render: function(y0) {
        // Render in batches of `dy` rows.
        wasm.instance.exports.render(y0, this.dy);

        const copy = this.pixels().slice();
        return Comlink.transfer(copy, [copy.buffer]);
    },
    rotateCamera: function(angle) {
        wasm.instance.exports.rotate_camera(angle);
    },
    moveCamera: function(distance) {
        wasm.instance.exports.move_camera(distance);
    },
    deinit: function() {
        wasm.instance.exports.deinitRenderer();
    }
};

Comlink.expose(obj);
