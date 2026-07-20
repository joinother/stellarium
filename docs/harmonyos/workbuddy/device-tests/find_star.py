import numpy as np
from PIL import Image, ImageFilter

IMG = "/Users/jiexuanyang/WorkBuddy/2026-07-19-01-20-21/device-tests/cap_center.jpeg"
OUT = "/Users/jiexuanyang/WorkBuddy/2026-07-19-01-20-21/device-tests/cap_center_marked.jpeg"

im = Image.open(IMG).convert("RGB")
W, H = im.size
arr = np.asarray(im).astype(np.float32)
lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]

# Blurred version to isolate point-like bright sources (stars) vs large UI blobs
blur = np.asarray(im.filter(ImageFilter.GaussianBlur(radius=9)).convert("L")).astype(np.float32)
starness = lum - blur  # high for compact bright points, ~0 for large flat UI

# Sky region mask: exclude status bar/top UI (y<175), bottom dock (y>1760),
# left rail (x<155), right margin (x>W-60)
sky = np.zeros_like(lum, dtype=bool)
sky[175:1760, 155:W-60] = True
work = np.where(sky, starness, -1e9)

candidates = []
for _ in range(15):
    y, x = np.unravel_index(np.argmax(work), work.shape)
    val = work[y, x]
    if val < 40:
        break
    candidates.append((int(x), int(y), float(val)))
    y0, y1 = max(0, y-36), min(H, y+37)
    x0, x1 = max(0, x-36), min(W, x+37)
    work[y0:y1, x0:x1] = -1e9

print("image", W, H)
print("Top point-star candidates (device px x,y, starness):")
for c in candidates:
    print(c)

marked = np.asarray(im).copy()
for i, (x, y, v) in enumerate(candidates[:6]):
    col = (255, 70, 70) if i == 0 else (70, 200, 255)
    marked[y-14:y+15, x-2:x+3] = col
    marked[y-2:y+3, x-14:x+15] = col
Image.fromarray(marked).save(OUT)
print("marked ->", OUT)

if candidates:
    bx, by, bv = candidates[0]
    print(f"TARGET device px = ({bx}, {by}) starness={bv:.1f}")
