# Design System Specification: Editorial Serenity

 

## 1. Overview & Creative North Star: "The Kinetic Atelier"

This design system rejects the "standard" box-model web. Our Creative North Star is **The Kinetic Atelier**—a space that feels like a high-end physical studio: airy, curated, and bathed in soft, natural light. 

 

We move beyond the "template" look by embracing **Intentional Asymmetry**. Do not feel forced to center-align every element. Use generous, "breathtaking" amounts of white space to isolate content, making every piece of information feel like a gallery artifact. By layering organic, pill-like shapes (radii up to `3rem`) over a base of cool, misty grays, we create a digital environment that reduces cognitive load and invites calm exploration.

 

---

 

## 2. Colors: Tonal Depth over Linework

Our palette is rooted in the "Seafoam and Slate" spectrum. We use the Primary `mint` (#2d695f) only for moments of high intentionality—never for decoration.

 

### The "No-Line" Rule

**Explicit Instruction:** Designers are prohibited from using 1px solid borders for sectioning. Structural boundaries must be defined solely through background color shifts. 

*   *Implementation:* Use `surface-container-low` (#f0f4f7) for a side panel sitting against a `surface` (#f7f9fb) main body.

 

### Surface Hierarchy & Nesting

Treat the UI as a series of stacked, fine papers. 

*   **Base:** `surface` (#f7f9fb)

*   **Elevated Containers:** Use `surface-container-lowest` (#ffffff) for "hero" cards to make them appear to float toward the user.

*   **Recessed Elements:** Use `surface-container-high` (#e3e9ed) for input fields or search bars to create a sense of tactile depth.

 

### The "Glass & Gradient" Rule

To elevate the experience, use **Glassmorphism** for floating navigation or overlay menus. 

*   *Token:* Use `surface` at 70% opacity with a `24px` backdrop-blur. 

*   *CTAs:* Instead of flat fills, apply a subtle linear gradient from `primary` (#2d695f) to `primary-dim` (#1f5c53) at a 135-degree angle to add "soul" and weight.

 

---

 

## 3. Typography: The Editorial Voice

We use **Plus Jakarta Sans** exclusively. Its modern geometric curves complement our organic border radii.

 

*   **Display (lg/md/sm):** Use `display-lg` (3.5rem) with `-0.02em` letter-spacing. These are your "billboard" moments. Keep them short and evocative.

*   **Headlines:** Use `headline-md` (1.75rem) in `on-surface` (#2c3437) for section headers. Ensure there is at least `48px` of top-margin to let the heading breathe.

*   **Body Text:** To ensure readability without breaking the "airy" feel, use `body-lg` (1rem) in `on-surface-variant` (#596064). The slightly darker gray provides necessary contrast against light backgrounds while remaining softer than pure black.

*   **Labels:** Use `label-md` (0.75rem) in All-Caps with `0.05em` tracking for a sophisticated, "label-maker" aesthetic on metadata.

 

---

 

## 4. Elevation & Depth: Atmospheric Volume

We do not use shadows to show "clickability"; we use them to show **Atmosphere**.

 

*   **The Layering Principle:** Place a `surface-container-lowest` card on a `surface-container-low` section. The change in hex code provides enough "lift" for the eye without visual clutter.

*   **Ambient Shadows:** For floating elements (Modals, Hovered Cards), use an extra-diffused shadow: `0 20px 40px rgba(44, 52, 55, 0.06)`. Note the use of `on-surface` (#2c3437) as the shadow tint rather than pure black.

*   **The "Ghost Border" Fallback:** If a border is required for accessibility, use the `outline-variant` token at 20% opacity. 100% opaque borders are strictly forbidden.

 

---

 

## 5. Components

 

### Buttons

*   **Primary:** High-pill (`rounded-full`), `primary` fill, `on-primary` text. Use a subtle shadow on hover to "lift" the button toward the cursor.

*   **Tertiary:** No background. Use `primary` text and a `2px` underline that appears only on hover.

 

### Cards & Lists

*   **Rule:** Forbid the use of divider lines. 

*   **Execution:** Separate list items using `12px` of vertical margin and a subtle `surface-container` background on the item container.

*   **Shape:** Use `rounded-lg` (2rem) for standard cards and `rounded-xl` (3rem) for large hero sections to maintain the "pill-like" aesthetic.

 

### Input Fields

*   **State:** Background should be `surface-container-highest`. Upon focus, the background transitions to `surface-container-lowest` with a `2px` "Ghost Border" in `primary`.

 

### Sophisticated Chips

*   **Selection:** Use `secondary-container` with `on-secondary-container` text. The shape must be `rounded-full` (pill).

 

---

 

## 6. Do’s and Don’ts

 

### Do:

*   **Do** allow elements to "bleed" off the edge of the grid if they are decorative.

*   **Do** use asymmetrical margins (e.g., a wider left margin than right) to create a custom, editorial feel.

*   **Do** use `primary-container` (#b2eee2) as a soft background highlight for active states.

 

### Don’t:

*   **Don’t** use a divider line to separate headers from content. Use white space.

*   **Don’t** use sharp 90-degree corners. Everything must feel "eroded" and soft.

*   **Don’t** use the `primary` mint green for large background blocks; it is too heavy for this "serene" system. Use it only for icons, buttons, and accents.

*   **Don’t** use standard "drop shadows." If it doesn't look like a soft glow, it's too dark.
