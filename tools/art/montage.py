"""Contact sheet from image files, run inside Blender: montage(out, cols, width, [paths])."""
import bpy, numpy as np


def montage(out, cols, w, paths):
    tiles = []
    for p in paths:
        img = bpy.data.images.load(p)
        iw, ih = img.size
        a = np.array(img.pixels[:], dtype=np.float32).reshape(ih, iw, 4)
        bpy.data.images.remove(img)
        h = int(w * ih / iw)
        ys = (np.arange(h) * ih / h).astype(int)
        xs = (np.arange(w) * iw / w).astype(int)
        tiles.append(a[ys][:, xs])
    while len(tiles) % cols:
        tiles.append(np.zeros_like(tiles[0]))
    rows = [np.concatenate(tiles[i:i + cols], 1) for i in range(0, len(tiles), cols)]
    full = np.concatenate(rows[::-1], 0)
    o = bpy.data.images.new("montage", full.shape[1], full.shape[0])
    o.pixels.foreach_set(full.ravel())
    o.filepath_raw = out
    o.file_format = 'JPEG'
    o.save()
    bpy.data.images.remove(o)
