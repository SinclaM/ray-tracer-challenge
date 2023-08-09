const text_decoder = new TextDecoder();
let console_log_buffer = "";
let wasm = undefined;

onmessage = async ({ data }) => {
    if ("init" in data) {
        const { memory, scene } = data;

        if (typeof(wasm) === "undefined") {
            wasm = {
                instance: undefined,
                pixels: undefined,

                init: function (obj) {
                    this.instance = obj.instance;
                },
                getString: function (ptr, len) {
                    const ab = new ArrayBuffer(len);
                    const arr = new Uint8Array(ab);
                    const sab_view = new Uint8Array(memory.buffer, ptr, len);
                    arr.set(sab_view);

                    return text_decoder.decode(arr);
                },
                // Convert a JavaScript string to a pointer to multi byte character array
                encodeString: function (string) {
                    const buffer = new TextEncoder().encode(string);
                    const pointer = this.instance.exports.wasmAlloc(buffer.length + 1); // ask Zig to allocate memory
                    const slice = new Uint8Array(
                        memory.buffer, // memory exported from Zig
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
                    memory: memory,
                    memoryBase: 0,
                    _throwError(pointer, length) {
                        const message = wasm.getString(pointer, length);
                        throw new Error(message);
                    },
                    jsConsoleLogWrite: function (ptr, len) {
                        console_log_buffer += wasm.getString(ptr, len);
                    },
                    jsConsoleLogFlush: function () {
                        console.log(console_log_buffer);
                        console_log_buffer = "";
                    },
                    loadObjData: function (name_ptr, name_len) {
                        name_ = wasm.getString(name_ptr, Number(name_len));

                        const request = new XMLHttpRequest();
                        request.open("GET", `obj/${name_}`, false);
                        request.send(null);

                        return wasm.encodeString(request.responseText);
                    },
                    updateCanvas: function (y) {
                        postMessage({ y });
                    }
                },
            };

            result = await WebAssembly.instantiateStreaming(
                fetch("ray-tracer-challenge.wasm"),
                importObject
            );
            wasm.init(result);
        }

        // Tell the WASM code to initialize the renderer.
        wasm.instance.exports.initRenderer(wasm.encodeString(scene));

        // If there was an error, bail out.
        if (!wasm.instance.exports.initRendererIsOk()) {
            const error_ptr = wasm.instance.exports.initRendererGetErrPtr();
            const error_len = wasm.instance.exports.initRendererGetErrLen();

            const error_message = wasm.getString(error_ptr, error_len);
            postMessage({ error: error_message });
        } else {
            postMessage({ init_done: null });
        }
    } else if ("render" in data) {
        const { dy } = data;
        try {
            // Render in batches of `dy` rows.
            wasm.instance.exports.render(dy);
        } catch (error) {
            postMessage({ error: error.message });
        } finally {
            // Clean up
            wasm.instance.exports.deinitRenderer();

            postMessage({ render_done: null });
        }
    }
};
