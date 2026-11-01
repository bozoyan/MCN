"""Reverse triangle winding of every indexed primitive in a GLB, in place.

The director renders with a right-handed projection on an engine that picks
winding for a left-handed one, so actor GLBs ship with reversed winding.
Usage: python3 scripts/reverse_glb_winding.py <in.glb> <out.glb>
"""
import json
import struct
import sys

src, dst = sys.argv[1], sys.argv[2]
data = bytearray(open(src, 'rb').read())
json_len = struct.unpack('<I', data[12:16])[0]
gltf = json.loads(data[20:20 + json_len])
bin_start = 20 + json_len + 8
formats = {5121: 'B', 5123: 'H', 5125: 'I'}
for mesh in gltf['meshes']:
    for primitive in mesh['primitives']:
        accessor = gltf['accessors'][primitive['indices']]
        view = gltf['bufferViews'][accessor['bufferView']]
        fmt = '<%d%s' % (accessor['count'], formats[accessor['componentType']])
        offset = bin_start + view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        indices = list(struct.unpack_from(fmt, data, offset))
        for i in range(0, len(indices), 3):
            indices[i + 1], indices[i + 2] = indices[i + 2], indices[i + 1]
        struct.pack_into(fmt, data, offset, *indices)
open(dst, 'wb').write(data)
