pub usingnamespace @cImport({
    @cDefine("_GNU_SOURCE", {});

    @cInclude("signal.h");
    @cInclude("malloc.h");
    @cInclude("pthread.h");

    @cInclude("linux/i2c-dev.h");
    @cInclude("i2c/smbus.h");
    @cInclude("sys/ioctl.h");
});
