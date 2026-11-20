#!/usr/bin/env python3
from __future__ import annotations
"""
Generate orthographically ray-traced 3D spherical planet & moon PNG icons
for HarmonyOS desktop widgets directly from Stellarium's own textures/*.png.

Each icon is a transparent 256x256 RGBA PNG (Saturn is 320x256 to accommodate
its tilted rings cleanly) with subtle limb darkening, atmospheric Rayleigh/haze
rim glow, and high-detail equirectangular-to-sphere projection.
"""

import math
import os
from pathlib import Path
from PIL import Image, ImageFilter

REPO_ROOT = Path(__file__).resolve().parent.parent
TEX_DIR = REPO_ROOT / "textures"
OUT_DIR = REPO_ROOT / "harmonyos" / "resources" / "base" / "media"


def clamp(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return lo if v < lo else (hi if v > hi else v)


def sample_bilinear(pixels, w: int, h: int, u: float, v: float):
    u = u % 1.0
    v = clamp(v, 0.0, 0.999999)
    fx = u * w - 0.5
    fy = v * h - 0.5
    x0 = int(math.floor(fx)) % w
    y0 = max(0, min(h - 1, int(math.floor(fy))))
    x1 = (x0 + 1) % w
    y1 = max(0, min(h - 1, y0 + 1))
    tx = fx - math.floor(fx)
    ty = fy - math.floor(fy)

    c00 = pixels[x0, y0]
    c10 = pixels[x1, y0]
    c01 = pixels[x0, y1]
    c11 = pixels[x1, y1]

    out = []
    for i in range(3):
        top = c00[i] * (1.0 - tx) + c10[i] * tx
        bot = c01[i] * (1.0 - tx) + c11[i] * tx
        out.append(top * (1.0 - ty) + bot * ty)
    return out[0], out[1], out[2]


def render_sphere(
    tex_name: str,
    out_name: str,
    size: int = 192,
    lon_offset_deg: float = 0.0,
    tilt_deg: float = 0.0,
    rim_rgb=(120, 180, 255),
    rim_strength: float = 0.0,
    limb_darkening: float = 0.32,
    light_dir=(0.45, -0.25, 0.86),
    ambient: float = 0.24,
    clouds_name: str | None = None,
    gamma: float = 1.0,
    radius_ratio: float = 0.43,
    saturn_rings: bool = False,
):
    tex_path = TEX_DIR / tex_name
    tex = Image.open(tex_path).convert("RGB")
    tw, th = tex.size
    tpix = tex.load()

    cpix = None
    cw = ch = 0
    if clouds_name:
        cpath = TEX_DIR / clouds_name
        if cpath.exists():
            cimg = Image.open(cpath).convert("RGBA")
            cw, ch = cimg.size
            cpix = cimg.load()

    rpix = None
    rw = 0
    if saturn_rings:
        rpath = TEX_DIR / "saturn_rings_radial.png"
        if rpath.exists():
            rimg = Image.open(rpath).convert("RGBA")
            rw = rimg.size[0]
            rpix = rimg.load()

    # Normalize light direction
    lx, ly, lz = light_dir
    llen = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / llen, ly / llen, lz / llen

    # Supersample 2x for crisp anti-aliased sphere limb & rings
    ss = 2
    W = size * ss
    H = size * ss
    cx = W * 0.5
    cy = H * 0.5
    R = (W * 0.212 if saturn_rings else W * radius_ratio)

    tilt_rad = math.radians(tilt_deg)
    cos_t = math.cos(tilt_rad)
    sin_t = math.sin(tilt_rad)
    lon_off = lon_offset_deg / 360.0

    # Saturn ring tilt (view elevation ~22 deg, roll ~-16 deg)
    ring_roll = math.radians(-16.0)
    cos_rr = math.cos(ring_roll)
    sin_rr = math.sin(ring_roll)
    ring_pitch = math.radians(22.0)
    sin_rp = math.sin(ring_pitch)
    cos_rp = math.cos(ring_pitch)

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()

    for y in range(H):
        dy = (y - cy) / R
        for x in range(W):
            dx = (x - cx) / R
            r2 = dx * dx + dy * dy

            # Ring ray intersection for Saturn (both back and front halves)
            ring_rgba_back = None
            ring_rgba_front = None
            if saturn_rings:
                # Rotate screen coords by ring roll
                rx = dx * cos_rr - dy * sin_rr
                ry = dx * sin_rr + dy * cos_rr
                # Project orthographic ray onto tilted ring plane (y_plane = ry / sin_rp)
                if abs(sin_rp) > 1e-4:
                    py_plane = ry / sin_rp
                    rad = math.sqrt(rx * rx + py_plane * py_plane)
                    if 1.24 <= rad <= 2.28:
                        u_ring = (rad - 1.24) / (2.28 - 1.24)
                        if rpix is not None:
                            idx = max(0, min(rw - 1, int(u_ring * (rw - 1))))
                            rc = rpix[idx, 0]
                            rr, rg, rb, ra = rc[0], rc[1], rc[2], rc[3]
                        else:
                            rr, rg, rb, ra = 220, 200, 165, 200
                        # Subtle Cassini division darkening + warm ring illumination
                        cassini = 1.0
                        if 0.56 <= u_ring <= 0.63:
                            cassini = 0.25
                        # Shadow of Saturn cast onto back-left of rings
                        shadow = 1.0
                        if py_plane < 0.0 and rx < 0.35 and (rx * rx + (py_plane * 0.65) ** 2) < 1.02:
                            shadow = 0.32
                        alpha_f = clamp((ra / 255.0) * 0.92 * cassini, 0.0, 0.95)
                        col = (
                            clamp(rr * 1.06 * shadow, 0, 255),
                            clamp(rg * 1.02 * shadow, 0, 255),
                            clamp(rb * 0.96 * shadow, 0, 255),
                            alpha_f,
                        )
                        if py_plane < 0.0:
                            ring_rgba_back = col
                        else:
                            ring_rgba_front = col

            out_r = out_g = out_b = out_a = 0.0

            # 1. Back ring behind planet
            if ring_rgba_back is not None:
                out_r, out_g, out_b, out_a = ring_rgba_back

            # 2. Planet sphere
            if r2 <= 1.0:
                nz = math.sqrt(max(0.0, 1.0 - r2))
                nx = dx
                ny = dy

                # Apply axial roll for texture mapping
                tx_n = nx * cos_t - ny * sin_t
                ty_n = nx * sin_t + ny * cos_t
                tz_n = nz

                lon = math.atan2(tx_n, tz_n) / (2.0 * math.pi) + 0.5 + lon_off
                lat = math.asin(clamp(ty_n, -1.0, 1.0)) / math.pi + 0.5

                tr, tg, tb = sample_bilinear(tpix, tw, th, lon, lat)

                if cpix is not None:
                    # Blend Earth clouds
                    cx_i = int((lon % 1.0) * cw) % cw
                    cy_i = max(0, min(ch - 1, int(clamp(lat, 0.0, 0.9999) * ch)))
                    cc = cpix[cx_i, cy_i]
                    ca = (cc[3] / 255.0) * 0.68
                    tr = tr * (1.0 - ca) + cc[0] * ca
                    tg = tg * (1.0 - ca) + cc[1] * ca
                    tb = tb * (1.0 - ca) + cc[2] * ca

                # Diffuse illumination + soft limb darkening
                ndotl = max(0.0, nx * lx + ny * ly + nz * lz)
                # Soft spherical shading so orb looks dimensional even before dynamic phase overlay
                shade = ambient + (1.0 - ambient) * (ndotl ** 0.78)
                limb = (1.0 - limb_darkening) + limb_darkening * (nz ** 0.55)
                illum = shade * limb

                sr = tr * illum
                sg = tg * illum
                sb = tb * illum

                # Atmospheric Fresnel rim glow
                if rim_strength > 0.0:
                    fresnel = ((1.0 - nz) ** 2.4) * rim_strength * (0.45 + 0.55 * ndotl)
                    sr = sr * (1.0 - fresnel * 0.45) + rim_rgb[0] * fresnel
                    sg = sg * (1.0 - fresnel * 0.45) + rim_rgb[1] * fresnel
                    sb = sb * (1.0 - fresnel * 0.45) + rim_rgb[2] * fresnel

                if gamma != 1.0:
                    sr = 255.0 * ((clamp(sr / 255.0)) ** gamma)
                    sg = 255.0 * ((clamp(sg / 255.0)) ** gamma)
                    sb = 255.0 * ((clamp(sb / 255.0)) ** gamma)

                # Anti-aliased edge alpha
                edge_dist = 1.0 - math.sqrt(r2)
                sphere_a = clamp(edge_dist * R * 1.1, 0.0, 1.0)
                # Composite sphere over back ring
                inv_sa = 1.0 - sphere_a
                out_r = sr * sphere_a + out_r * out_a * inv_sa
                out_g = sg * sphere_a + out_g * out_a * inv_sa
                out_b = sb * sphere_a + out_b * out_a * inv_sa
                out_a = sphere_a + out_a * inv_sa
                if out_a > 1e-4:
                    out_r /= out_a
                    out_g /= out_a
                    out_b /= out_a
            elif rim_strength > 0.0:
                # Soft outer atmospheric halo outside limb
                dist_out = math.sqrt(r2) - 1.0
                if dist_out < 0.14:
                    halo = math.exp(-dist_out * 28.0) * rim_strength * 0.42
                    if halo > 0.01:
                        inv_h = 1.0 - halo
                        out_r = rim_rgb[0] * halo + out_r * out_a * inv_h
                        out_g = rim_rgb[1] * halo + out_g * out_a * inv_h
                        out_b = rim_rgb[2] * halo + out_b * out_a * inv_h
                        out_a = halo + out_a * inv_h
                        if out_a > 1e-4:
                            out_r /= out_a
                            out_g /= out_a
                            out_b /= out_a

            # 3. Front ring in front of planet
            if ring_rgba_front is not None:
                fr, fg, fb, fa = ring_rgba_front
                inv_fa = 1.0 - fa
                new_a = fa + out_a * inv_fa
                if new_a > 1e-4:
                    out_r = (fr * fa + out_r * out_a * inv_fa) / new_a
                    out_g = (fg * fa + out_g * out_a * inv_fa) / new_a
                    out_b = (fb * fa + out_b * out_a * inv_fa) / new_a
                    out_a = new_a

            if out_a > 0.003:
                px[x, y] = (
                    int(clamp(out_r, 0, 255)),
                    int(clamp(out_g, 0, 255)),
                    int(clamp(out_b, 0, 255)),
                    int(clamp(out_a * 255.0, 0, 255)),
                )

    final_img = img.resize((size, size), Image.Resampling.LANCZOS)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / out_name
    final_img.save(out_path, optimize=True)
    print(f"generated {out_path.name} ({out_path.stat().st_size // 1024} KB)")


def main():
    # Moon: front-lit full lunar disk (dynamic phase terminator is overlaid in ArkUI!)
    render_sphere(
        "moon.png", "widget_orb_moon.png",
        lon_offset_deg=0.0, tilt_deg=-8.0,
        rim_rgb=(215, 224, 245), rim_strength=0.14,
        limb_darkening=0.22, light_dir=(0.15, -0.10, 0.98), ambient=0.72, gamma=0.95,
    )
    # Earth: Asia-Pacific/Eurasia view with clouds & Rayleigh blue atmospheric rim
    render_sphere(
        "earthmap.png", "widget_orb_earth.png",
        clouds_name="earth-clouds.png",
        lon_offset_deg=110.0, tilt_deg=-14.0,
        rim_rgb=(105, 185, 255), rim_strength=0.72,
        limb_darkening=0.28, light_dir=(0.35, -0.22, 0.91), ambient=0.35, gamma=0.92,
    )
    # Mars: Syrtis Major / Valles Marineris hemisphere with dusty peach-amber limb
    render_sphere(
        "mars.png", "widget_orb_mars.png",
        lon_offset_deg=-40.0, tilt_deg=-15.0,
        rim_rgb=(238, 165, 118), rim_strength=0.48,
        limb_darkening=0.34, light_dir=(0.40, -0.20, 0.89), ambient=0.28, gamma=0.95,
    )
    # Saturn: Banded golden globe + tilted 3D rings with Cassini division & shadow
    render_sphere(
        "saturn.png", "widget_orb_saturn.png",
        lon_offset_deg=20.0, tilt_deg=-16.0,
        rim_rgb=(245, 218, 162), rim_strength=0.36,
        limb_darkening=0.36, light_dir=(0.42, -0.22, 0.88), ambient=0.32,
        saturn_rings=True,
    )
    # Jupiter: Cloud belts & Great Red Spot hemisphere
    render_sphere(
        "jupiter.png", "widget_orb_jupiter.png",
        lon_offset_deg=-60.0, tilt_deg=-8.0,
        rim_rgb=(240, 210, 175), rim_strength=0.32,
        limb_darkening=0.38, light_dir=(0.42, -0.18, 0.89), ambient=0.30,
    )
    # Titan: Golden-orange tholin haze globe
    render_sphere(
        "titan.png", "widget_orb_titan.png",
        lon_offset_deg=15.0, tilt_deg=-10.0,
        rim_rgb=(255, 178, 86), rim_strength=0.78,
        limb_darkening=0.36, light_dir=(0.38, -0.22, 0.90), ambient=0.32, gamma=0.92,
    )
    # Venus: Bright creamy sulfuric cloud deck
    render_sphere(
        "venus.png", "widget_orb_venus.png",
        lon_offset_deg=40.0, tilt_deg=-5.0,
        rim_rgb=(255, 232, 180), rim_strength=0.58,
        limb_darkening=0.30, light_dir=(0.38, -0.20, 0.90), ambient=0.38, gamma=0.94,
    )
    # Neptune: Deep cobalt methane atmosphere with cyan rim
    render_sphere(
        "neptune.png", "widget_orb_neptune.png",
        lon_offset_deg=30.0, tilt_deg=-18.0,
        rim_rgb=(96, 188, 255), rim_strength=0.68,
        limb_darkening=0.36, light_dir=(0.38, -0.20, 0.90), ambient=0.34, gamma=0.90,
    )
    # Uranus: Pale ice-cyan globe
    render_sphere(
        "uranus.png", "widget_orb_uranus.png",
        lon_offset_deg=0.0, tilt_deg=25.0,
        rim_rgb=(156, 234, 245), rim_strength=0.55,
        limb_darkening=0.28, light_dir=(0.35, -0.20, 0.91), ambient=0.40,
    )
    # Mercury: Cratered warm grey globe
    render_sphere(
        "mercury.png", "widget_orb_mercury.png",
        lon_offset_deg=20.0, tilt_deg=-5.0,
        rim_rgb=(205, 198, 188), rim_strength=0.12,
        limb_darkening=0.36, light_dir=(0.45, -0.22, 0.86), ambient=0.26,
    )
    # Pluto: Tombaugh Regio + ice-blue tenuous nitrogen limb haze
    render_sphere(
        "pluto.png", "widget_orb_pluto.png",
        lon_offset_deg=180.0, tilt_deg=-15.0,
        rim_rgb=(128, 194, 255), rim_strength=0.52,
        limb_darkening=0.32, light_dir=(0.42, -0.22, 0.88), ambient=0.30,
    )

    # Also build a scratch preview contact sheet to inspect visually
    names = [
        "widget_orb_moon.png", "widget_orb_earth.png", "widget_orb_mars.png",
        "widget_orb_saturn.png", "widget_orb_jupiter.png", "widget_orb_titan.png",
        "widget_orb_venus.png", "widget_orb_neptune.png", "widget_orb_uranus.png",
        "widget_orb_mercury.png", "widget_orb_pluto.png",
    ]
    cols = 4
    rows = math.ceil(len(names) / cols)
    cell = 160
    sheet = Image.new("RGB", (cols * cell, rows * cell), (10, 15, 28))
    for i, n in enumerate(names):
        im = Image.open(OUT_DIR / n).resize((cell - 16, cell - 16), Image.Resampling.LANCZOS)
        r = i // cols
        c = i % cols
        sheet.paste(im, (c * cell + 8, r * cell + 8), im)
    preview_dir = Path("/Users/jiexuanyang/.gemini/antigravity/brain/3fe92827-0a51-4183-8652-d2b423eac3b1/scratch")
    preview_dir.mkdir(parents=True, exist_ok=True)
    sheet.save(preview_dir / "widget_orbs_contact_sheet.png")
    print("saved preview sheet:", preview_dir / "widget_orbs_contact_sheet.png")


if __name__ == "__main__":
    main()
