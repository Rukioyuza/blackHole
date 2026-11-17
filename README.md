<h1 align="left">Singularity</h1>

<p align="left">
  <img src="https://img.shields.io/badge/Roblox-181717?style=for-the-badge&logo=roblox&logoColor=white" />
  <img src="https://img.shields.io/badge/Luau-181717?style=for-the-badge&logo=luau&logoColor=00A2FF" />
  <img src="https://img.shields.io/badge/EditableImage-181717?style=for-the-badge&logo=robloxstudio&logoColor=white" />
</p>

The fastest 2D black hole implementation in Roblox. A lensed starfield and a swirling accretion disk, rendered in real time with two reads and one write per pixel.

---

### About

Singularity draws a black hole onto an **EditableImage** without doing any per-frame maths on pixels.

Every square root, arctangent and lens equation is solved once at startup. After that, each frame is a handful of block copies and a single branchless loop.

The result is gravitational lensing, an Einstein ring and Keplerian disk rotation at the cost of a memory copy.

---

### Techniques

<p>
  <img src="https://img.shields.io/badge/Lookup-Gather_Map-181717?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Motion-Block_Copy-181717?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Texels-u32-181717?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Loop-Branchless-181717?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Codegen-Native-181717?style=for-the-badge" />
</p>

- **Gather map.** Each pixel's source texel is precomputed, so a frame is pure indirection.
- **Block copy motion.** Stars drift in two `buffer.copy` calls; each disk ring rotates in two more.
- **Whole texels.** Pixels move as single `u32` values, not four bytes.
- **Void texel.** The event horizon points at one shared black texel, so the loop never branches.
- **Squared distances.** Region tests and star lensing need no square root.
- **Native codegen.** The frame loop compiles to machine code with `--!native`.

---

### Physics

<p>
  <img src="https://img.shields.io/badge/Lensing-Point_Mass-181717?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Orbits-Keplerian-181717?style=for-the-badge" />
</p>

- Stars follow the thin lens equation, `β = θ(1 − θE² / θ²)`.
- Disk rings shear at angular speeds proportional to `r^-1.5`.
- Colour follows a black-body ramp from white-hot core to deep red edge.

---

### Usage

1. Place the script in a **LocalScript** under `StarterPlayerScripts`.
2. For published experiences, enable **Allow Mesh / Image APIs** in Experience Settings under Security.
3. Press play.

---

### Configuration

| Constant | Default | Purpose |
| --- | --- | --- |
| `FRAME_SIZE` | `512` | Output resolution in pixels |
| `HORIZON_RADIUS` | `0.12` | Event horizon size |
| `DISK_RADIUS` | `0.42` | Accretion disk outer edge |
| `EINSTEIN_RADIUS` | `0.5` | Lensing strength |
| `STAR_DRIFT` | `24` | Starfield speed in texels per second |
| `INNER_ORBITS_PER_SECOND` | `0.5` | Disk rotation speed |

---
