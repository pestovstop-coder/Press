# TASK 013 — Shadow Audit

## Scope and confidence

This is a static audit of the committed Godot project at `2ecd3a3`. The user-reported symptoms are treated as observed input: harsh stair-stepping and shadows that look too dark. Godot 4.7.2 is not installed in this environment, so there was no renderer execution, visual inspection, screenshot, camera-orbit comparison, or performance measurement. The hypotheses below are not presented as confirmed visual causes. **No lighting, shadow, renderer, environment, or material settings were changed for this audit.**

## Current values before this task

### Renderer, map and filter

| Setting | Current value |
|---|---|
| Godot target / renderer | Godot 4.7.x project feature; `gl_compatibility` desktop/mobile/web |
| Directional shadow map size | 4096 px desktop; 2048 px mobile override (`project.godot`) |
| Directional soft-shadow filter | 3 = Soft Medium desktop; 2 = Soft Low mobile override |
| Positional shadow filter | Not overridden; no local light casts shadows |
| Directional caster | `Sun` only; shadows enabled |

### Sun (`scenes/main.tscn`)

| Property | Current value |
|---|---|
| Rotation | `(-50°, 165°, 0°)` |
| Color / energy | `Color(1, 0.99, 0.97, 1)` / `0.32` |
| Shadow mode | `0` — orthogonal, one unsplit directional shadow view |
| Max distance | `45.0` |
| Fade start | Effective default `0.8` (not explicitly authored) |
| Bias / normal bias | `0.02` / `0.25` |
| Blur | `1.5` |
| Pancake size | Effective default `20.0` (not explicitly authored) |
| Angular distance / shadow opacity | Effective defaults `0.0` / `1.0`; PCSS is not active |
| Directional depth precision | 16-bit setting effective default `true` (not explicitly authored) |

### Environment, fill lights, camera, and materials

- `WorldEnvironment`: background mode 1, color `Color(0.13, 0.14, 0.15, 1)`; ambient source Color; ambient color `Color(0.96, 0.95, 0.93, 1)`; energy `0.28`; sky contribution `0.0`.
- Six ceiling `OmniLight3D`s (all color `Color(1, 0.97, 0.92, 1)`, range `4.5`, attenuation `1.4`, `shadow_enabled = false`): `PanelLeftRear` at `(-3, 2.7, -2.7)`, `PanelLeftFront` at `(-3, 2.7, 0.4)`, `PanelRightRear` at `(3, 2.7, -2.7)`, and `PanelRightFront` at `(3, 2.7, 0.4)` each energy `0.18`; `PanelLeftCorridor` at `(-3, 2.7, 3.1)` and `PanelRightCorridor` at `(3, 2.7, 3.1)` each energy `0.22`.
- Two window `SpotLight3D`s (color `Color(0.98, 0.99, 1, 1)`, energy `0.18`, range `8`, attenuation `1.2`, angle `38°`, angle attenuation `0.7`, `shadow_enabled = false`): `WindowLeftDaylight` at `(-3.55, 1.85, -4.7)`, rotation `(-22°, 180°, 0°)`; `WindowRightDaylight` at `(2.45, 1.85, -4.7)`, same rotation.
- The orthographic camera starts at size `16`, supports zoom from `6` to `26`, orbits at nominal radius `30 m`, and pans the view focus within approximately `x ±6 m`, `z ±4.25 m`. At 16:9, the unzoomed vertical/horizontal view span is about `16 × 28.44 m`; at maximum zoom-out it is `26 × 46.22 m`. The floor is `12 × 8.5 m`, so the camera view can include substantially more than the floor area. If the renderer's shadow projection follows this view coverage, the map can spend texels outside the room; the actual shadow-map frustum is renderer-generated and cannot be confirmed from the scene text alone. There is no ceiling.
- Wall material is matte, light beige (`Color(0.831373, 0.815686, 0.772549, 1)`), roughness `0.92`, metallic `0`. The floor is a light beige/grey speckled linoleum texture, roughness `0.92`, metallic `0`, triplanar at 2 repeats/m. Doorway accent is `Color(0.45, 0.48, 0.52, 1)`, roughness `0.9`; window frame is `Color(0.38, 0.40, 0.41, 1)`, roughness `0.88`, metallic `0.15`. The room finishes are mostly bright and matte, so they do not intrinsically explain deep room-wide shadows. Floor texture variation and grey/darker doorway/window trim can make local shadow/contact contrast more noticeable.
- Existing `office_desk.glb` has untextured `light_natural_wood` (`baseColor ≈ (0.722, 0.541, 0.329)`, roughness `0.72`, metallic `0`) and `graphite_metal` (`baseColor ≈ (0.067, 0.078, 0.090)`, roughness `0.48`, metallic `0.75`). The new `employee_workstation.glb` contains 7 PBR material definitions (baseColor textures, roughness `0.5` for six and about `0.746` for one) and 2 embedded images. Dark graphite or palette texels can make furniture shadow regions feel darker than the bright floor/walls; they do not cause shadow-map stair-stepping. Exact imported Godot material appearance remains unverified here.

## A. Stair-stepping

### Likely contributors

1. **Finite map resolution and coverage.** A 4096² directional map is not low in isolation, but its useful texel density depends on the projection volume Godot renders into it. An orthographic camera with a large zoom range and camera orbit can make a large/shifted region relevant. A single unsplit orthogonal map spreads available texels over its current coverage; hard map edges remain quantized even with a soft filter.
2. **Filter level is not a resolution increase.** Soft Medium (3) improves edge sampling relative to the previous Soft Low (2), but it cannot restore geometric detail missing from the map. It may leave visible stair-steps; increasing filter quality costs additional shadow-map samples and can soften fine contact detail.
3. **`directional_shadow_max_distance = 45`.** Godot documents this as the maximum distance for directional shadow splits. Since the current mode is orthogonal (`0`), the 45 m value is not automatically proof that the orthogonal map is spread over 45 m; it may have less or different influence than it would with parallel splits. The camera orbit radius is 30 m and at the widest zoom the view itself is broad, so blindly reducing the value could also remove shadows. Its actual effect in this Compatibility/orthogonal setup must be verified with controlled runtime captures.
4. **Orthogonal mode and orbit.** One map avoids cascade/split boundaries, which is attractive for this compact isometric scene. When the camera rotates or moves, the shadow projection can still shift across texels and expose aliasing/shimmer. Switching to 2 or 4 parallel splits may improve near detail in some views but adds map work and possible split transitions; it is not an evidence-based first fix for this orthographic camera.
5. **Bias is not an anti-aliasing control.** `shadow_bias = 0.02` and `shadow_normal_bias = 0.25` are already below Godot's generic Light3D defaults (`0.1` / `2.0`). A too-large value can detach the shadow from the caster; a too-small value can cause self-shadowing/acne. Bias may make an edge look displaced or contaminated, but changing it will not smooth map quantization. The effective pancake size is also the engine default `20.0`; reducing it can improve depth precision but may clip large casters near the frustum edge. None of these values can be judged as wrong from static scene text alone.
6. **Blur and unsupported PCSS.** Blur `1.5` is already above the generic default `1.0`; raising it further can hide jaggies but may add grain, wash out contact shadows, and cost performance. PCSS via `light_angular_distance` is not available for directional shadows in the Compatibility renderer, so it is not a viable soft-sun solution here.

### Useful controlled tests and trade-offs

| Candidate | Expected effect | Cost / risk |
|---|---|---|
| Keep map 4096; compare Soft Medium (3) against Soft High (4) | More filter samples can reduce visible edge stepping and stabilize filtering | More per-pixel shadow sampling; High applies a 1.5× constant-blur multiplier for a zero angular-size light, so blur becomes softer and may reduce contact readability |
| Test map size 8192 only if 4096 + High still aliases | Higher spatial resolution directly addresses map quantization | Four times the map texels versus 4096²; more memory/bandwidth and shadow rendering cost. Do not assume it meets the minimum GPU target |
| A/B 45 m against a scene-covering smaller distance only after runtime confirms the property affects this mode | If the effective projection/culling volume shrinks, detail may improve; can also reduce unnecessary casters | Risk of cut-off/fading on far edges, wide zoom, pan, or camera rotation; orthogonal mode may not respond as expected |
| Compare orthogonal mode 0 with 2 splits only as a separate experiment | Splits can allocate more detail near the view in some configurations | Extra shadow rendering and possible visible split transitions/popping while orbiting; behavior must be checked at all angles |
| Keep biases fixed for the first A/B | Isolates resolution/filter changes | If a genuine acne or detachment defect remains, tune bias in a separate, small sweep; either direction can trade one artifact for the other |

## B. Shadows perceived as too dark

### Likely contributors

- Ambient is uniform Color lighting at energy `0.28` and sky contribution is disabled. It does not provide physically accumulated bounce light or spatially varying indirect fill. Shadowed pixels therefore may be dominated by relatively low ambient illumination.
- There are eight shadowless fill lights, but they are local and have ranges of 4.5 m (ceiling panels) and 8 m (window fills). With attenuation, coverage varies by location; they cannot guarantee equal fill in every corner or behind every wall/furniture arrangement. Their lack of shadows is intentional and should be retained for this task.
- Sun energy is `0.32`, but Godot's Light3D energy and Environment ambient energy are not directly comparable photometric quantities. Their numeric ratio alone does not establish scene contrast. The user report is consistent with insufficient ambient/local fill, but it needs a render capture to distinguish that from display exposure, material response, or occlusion.
- The floor and wall albedos are light and rough (`0.92` roughness), so they are not obvious dark-surface culprits. The floor's speckle and furniture's embedded palette textures can make a shadowed region feel more mottled or locally darker; changing those materials is not justified without a rendered A/B.
- Shadow opacity remains at the Light3D default `1.0`; no other shadow caster adds overlapping shadow layers. Excessive darkening is therefore more plausibly a lack of fill/ambient or an appearance/exposure issue than cumulative shadow sources.

### Candidate fill tests and trade-offs

| Candidate | Expected effect | Cost / risk |
|---|---|---|
| A/B ambient energy `0.28` versus `0.36`, holding all else fixed | Raises the floor of illumination in all shadowed regions, with no additional shadow-map cost | Can flatten contrast, brighten highlights, and wash out material color; global effect, not localized bounce light |
| If specific corners remain dark, test a modest increase to nearby existing Omni/Spot fill energy or range one source at a time | Local fill can target gaps without raising all ambient | More per-light shading and overlap; can flatten contrast or create uneven hot spots. Keep these sources shadowless |
| Check exposure/output and imported material appearance at fixed display settings | Rules out presentation/material contrast as a confound | Diagnostic only; do not change materials or renderer until a capture identifies the cause |

## Recommended next Godot test set

No values below have been applied. For an interpretable comparison, capture the same desk, workstation, low/high walls, and room joins at 1920×1080 in front, side, and intermediate orbit views; record GPU, renderer, zoom, FPS/frame time, and shadow appearance.

1. **Baseline capture:** current values as listed above.
2. **Edge-filter pass:** map 4096, Soft High (4), keep Sun blur `1.5`, bias `0.02`, normal bias `0.25`, mode `0`, max distance `45`; compare edge softness and contact detail to baseline.
3. **Coverage pass:** after confirming whether max distance affects the active orthogonal map, compare `45` with a lower value that still covers the complete room at zoom 26 and maximum pan. Keep all other settings at baseline. If the renderer confirms mode 0 ignores the distance for map coverage, do not spend time tuning it in this mode.
4. **Resolution fallback:** only if edge filtering/coverage are insufficient, test map size 8192 with the best acceptable filter and measure memory/FPS. This is a high-quality option, not the default recommendation for weak hardware.
5. **Fill pass:** separately compare ambient `0.28` and `0.36` with shadow settings fixed. If global fill washes out the room, revert and test only one relevant existing fill source at a time.
6. Test any split-mode change last and separately; verify transitions during complete orbit, especially wall joins and furniture contact shadows.

Acceptance requires no new detachment/acne, retained wall/junction shadows through camera orbit, readable but not washed-out furniture shadows, and recorded performance on target hardware. Until that runtime work is done, the task output is an audit and test plan, **not a claim that shadows are fixed**.
