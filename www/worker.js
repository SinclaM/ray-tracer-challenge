importScripts("./comlink.js");

const text_decoder = new TextDecoder();
let console_log_buffer = "";
let wasm = undefined;

const obj = {
    id: undefined,
    width: undefined,
    height: undefined,
    pixels: undefined,

    init: async function(id, scene) {
        this.id = id;
        wasm = {
            instance: undefined,
            pixels: undefined,

            init: function (instance) {
                this.instance = instance;
            },
            getString: function (ptr, len) {
                const view = new Uint8Array(this.instance.exports.memory.buffer, ptr, len);
                return text_decoder.decode(view);
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
                    console_log_buffer += wasm.getString(ptr, len);
                },
                jsConsoleLogFlush: function () {
                    console.log(`[Worker ${id}] ${console_log_buffer}`);
                    console_log_buffer = "";
                },
                loadObjData: function (name_ptr, name_len) {
                    name_ = wasm.getString(name_ptr, Number(name_len));

                    const request = new XMLHttpRequest();
                    request.open("GET", `obj/${name_}`, false);
                    request.send(null);

                    return wasm.encodeString(request.responseText);
                }
            },
        };


        await WebAssembly.instantiateStreaming(fetch("ray-tracer-challenge.wasm"), importObject).then(
            (obj) => wasm.init(obj.instance),
        );

        // Tell the WASM code to initialize the renderer.
        wasm.instance.exports.initRenderer(wasm.encodeString(scene));

        // If there was an error, bail out.
        if (!wasm.instance.exports.initRendererIsOk()) {
            const error_ptr = wasm.instance.exports.initRendererGetErrPtr();
            const error_len = wasm.instance.exports.initRendererGetErrLen();

            const error_message = wasm.getString(error_ptr, error_len);
            throw new Error(error_message);
        } else {
            pixels_ptr = wasm.instance.exports.initRendererGetPixels();
            this.width = wasm.instance.exports.initRendererGetWidth();
            this.height = wasm.instance.exports.initRendererGetHeight();

            this.pixels = () => new Uint8ClampedArray(
                wasm.instance.exports.memory.buffer,
                pixels_ptr,
                this.width * this.height * 4
            );

            return { width: this.width, height: this.height };
        }
    },
    render: function(y0, dy) {
        // Render in batches of `dy` rows.
        wasm.instance.exports.render(y0, dy);

        const start = y0 * this.width * 4;
        const end = start + dy * this.width * 4;
        const copy = this.pixels().slice(start, end);
        return Comlink.transfer(copy, [copy.buffer]);
    },
    deinit: function() {
        wasm.instance.exports.deinitRenderer();
    }
};

Comlink.expose(obj);
