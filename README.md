# binary xray

Peek inside a binary to see which lines are executing in realtime.

Works on Linux with binaries built in debug mode.

https://user-images.githubusercontent.com/1291012/220166020-2725b953-20f5-48e9-a0b6-cec334201072.mp4

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
git clone https://github.com/charles-l/binary-xray
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

