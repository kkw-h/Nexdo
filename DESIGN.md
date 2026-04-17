# Design System Specification: Editorial Mint
 
## 1. Overview & Creative North Star
The Creative North Star for this design system is **"The Serene Curator."** 
 
Moving away from the sterile, rigid grids of utility-first applications, this system prioritizes a high-end editorial feel. It treats task management as a mindful ritual rather than a chore. We achieve this through "Breathable Depth"—using expansive whitespace, soft organic shapes, and a sophisticated tonal palette that favors background shifts over harsh outlines. The goal is to create an interface that feels like a premium physical planner resting on a frosted glass desk.
 
## 2. Colors & Tonal Logic
Our palette is rooted in botanical teals and mints, designed to reduce cognitive load.
 
### Color Strategy
*   **The "No-Line" Rule:** 1px solid borders are strictly prohibited for sectioning. Structural separation must be achieved through background color shifts. For example, a card (`surface_container_lowest`) should sit on a background of `surface_container`, using value contrast rather than line weight to define its bounds.
*   **Surface Hierarchy & Nesting:** Use the `surface` tiers to create physical presence. 
    *   **Level 0 (Base):** `surface` (#f1fbf9) – The global canvas.
    *   **Level 1 (Sections):** `surface_container_low` (#e8f7f4) – Grouping large content areas.
    *   **Level 2 (Active Cards):** `surface_container_lowest` (#ffffff) – The primary focal point for tasks.
*   **The "Glass & Gradient" Rule:** Floating elements, such as bottom navigation bars or active headers, should utilize a `surface_bright` tint with a `backdrop-blur` of 20px. 
*   **Signature Textures:** Use a subtle linear gradient for primary CTAs: `primary` (#006c5a) to `primary_dim` (#005e4f) at a 135° angle to provide a velvet-like depth.
 
| Token | Hex | Role |
| :--- | :--- | :--- |
| `primary` | #006c5a | Brand anchor, high-emphasis actions. |
| `primary_container` | #8cecd3 | Soft mint backgrounds for active states. |
| `surface` | #f1fbf9 | The soft "Paper" base of the application. |
| `surface_container_highest` | #d1e7e4 | Depth for inactive or recessed elements. |
| `on_surface_variant` | #4f6361 | Secondary text with reduced optical weight. |
| `tertiary_container` | #fdb64b | Warm accents for alerts or "high energy" tags. |
 
## 3. Typography: The Editorial Voice
We use **Plus Jakarta Sans** for its modern, geometric clarity and generous x-height, which ensures legibility even at smaller scales.
 
*   **Display & Headlines:** Use `headline-lg` (2rem) with `on_surface` (#233634) for page titles. Bold weights should be used sparingly to maintain an airy, sophisticated feel.
*   **Contextual Titles:** `title-md` (1.125rem) is the workhorse for card headers. It provides enough presence to lead the eye without crowding the container.
*   **The Label System:** `label-md` and `label-sm` are always paired with `surface_container_highest` background chips to create a "tag" aesthetic that feels distinct from body copy.
 
## 4. Elevation & Depth
In this design system, shadows are a last resort, not a default. We convey hierarchy through **Tonal Layering**.
 
*   **The Layering Principle:** Rather than "lifting" an object with a shadow, "sink" the background. To make a task card pop, place a `#ffffff` card on an `#e1f1ef` background.
*   **Ambient Shadows:** Where floating interaction is required (e.g., FABs or modals), use an "Ambient Mint" shadow:
    *   `box-shadow: 0 12px 32px -8px rgba(0, 108, 90, 0.08);`
    *   The shadow is tinted with the `primary` color to mimic natural light passing through a translucent green surface.
*   **The Ghost Border Fallback:** If a border is required for accessibility (e.g., in high-contrast modes), use `outline_variant` (#a1b6b4) at **15% opacity**. Never use a 100% opaque border.
*   **Roundedness Scale:**
    *   `DEFAULT`: 1rem (16px) - For standard task cards.
    *   `md`: 1.5rem (24px) - For parent containers and hero sections.
    *   `full`: 9999px - For chips, pills, and action buttons.
 
## 5. Components
 
### Cards & Lists
*   **Card Anatomy:** Use `surface_container_lowest` for the card body. Internal padding must be a minimum of `1.5rem` (24px).
*   **Anti-Divider Rule:** Forbid the use of 1px dividers between list items. Use vertical whitespace (16px–24px) or a subtle 4px margin with a background color shift to separate tasks.
 
### Buttons & Inputs
*   **Primary Button:** Pill-shaped (`rounded-full`). Background uses the `primary` to `primary_dim` gradient. Text is `on_primary` (#e3fff5).
*   **Selection Chips:** Use `primary_container` for the active state and `surface_container_highest` for the inactive state. Typography should be `label-md`.
*   **Checkboxes:** Custom rounded squares (8px radius). When checked, use a `primary` fill with a white checkmark. When unchecked, use a 2px `outline_variant` at 40% opacity.
 
### Floating Action Button (FAB)
*   The FAB is the system’s "Jewel." It should use a Glassmorphic effect: `surface_container_lowest` with 80% opacity and a 12px backdrop blur, or a solid `primary_container` if high visibility is needed.
 
## 6. Do's and Don'ts
 
### Do
*   **Do** use asymmetrical margins to create editorial interest (e.g., a larger top margin for section headers).
*   **Do** use `on_surface_variant` for metadata like dates or categories to create a clear visual hierarchy.
*   **Do** embrace "Mint-on-Mint" layering to create a cohesive, branded environment.
 
### Don't
*   **Don't** use pure black (#000000) for text. Always use `on_surface` (#233634) to maintain the soft botanical palette.
*   **Don't** use "Drop Shadows" that are grey or high-opacity. They break the serenity of the "Curator" aesthetic.
*   **Don't** cram content. If a card feels tight, increase the parent container's padding rather than shrinking the font.
