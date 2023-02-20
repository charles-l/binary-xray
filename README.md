# binary xray

Peek inside a binary to see which lines are executing in realtime.

### building
Install dependencies
```
apt install binutils-dev
```

Clone and build dynamorio. More instructions on [their website](https://dynamorio.org/page_building.html).
```
git clone --recursive https://github.com/DynamoRIO/dynamorio.git
cd dynamorio && mkdir build && cd build
cmake ..
make -j
```

Build `bx`.
```
git clone <this repo>
cd binary-xray
zig build -Ddynamorio-build=/path/to/dynamorio/build/
```

### usage

```
# instrument the binary
drrun -c zig-out/lib/libbx.so function_to_instrument -- path/to/executable

# open the gui to observe which lines are executing
./zig-out/bin/bxgui
```

