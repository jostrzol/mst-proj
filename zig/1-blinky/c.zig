pub usingnamespace @cImport({
    @cDefine("_GNU_SOURCE", {});

    @cInclude("signal.h");
    @cInclude("malloc.h");
    @cInclude("pthread.h");
});
