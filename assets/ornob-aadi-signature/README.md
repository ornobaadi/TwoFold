# Ornob Aadi — signature assets

Two weights: `regular` (subtle) and `bold` (more visible at small sizes — recommended for footers).

| File | Use |
|---|---|
| `ornob-aadi-signature-*.svg` | **Best option.** Uses `fill="currentColor"`, so it takes the text color of wherever you put it. |
| `*-dark.png` | Dark ink (#111) on transparent — for light backgrounds. 800px tall. |
| `*-light.png` | White ink on transparent — for dark backgrounds. 800px tall. |

## Make it follow your app's theme automatically

**Inline SVG (React / Next.js)** — paste the SVG contents into a component; color follows `color`:

```jsx
<footer className="text-neutral-900 dark:text-neutral-100">
  <Signature className="h-8 w-auto opacity-80" aria-label="Ornob Aadi" />
</footer>
```

**As a file (any framework) — CSS mask**, so one file works with any color:

```css
.signature {
  height: 32px;
  aspect-ratio: 924 / 391;
  background-color: currentColor;            /* or var(--foreground), var(--primary)... */
  -webkit-mask: url(/ornob-aadi-signature-bold.svg) center / contain no-repeat;
          mask: url(/ornob-aadi-signature-bold.svg) center / contain no-repeat;
}
```

```html
<span class="signature" role="img" aria-label="Ornob Aadi"></span>
```

Note: a plain `<img src="...svg">` can't inherit `currentColor` — it will render black. Use inline SVG or the mask approach above.
