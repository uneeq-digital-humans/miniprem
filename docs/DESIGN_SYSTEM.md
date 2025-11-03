# UneeQ Documentation Design System

This document defines the unified design language used across UneeQ documentation projects (MiniPrem, etc.). The design system follows the official UneeQ brand refresh (March 2023).

## Brand Overview

The UneeQ brand (March 2023) emphasizes bold, modern design with a vibrant color palette suitable for digital human platforms and enterprise documentation.

## Typography

### Font Families
- **Headings**: Manrope Bold (700 weight)
- **Subheadings**: Manrope Regular (400 weight)
- **Body Text**: Inter Regular (400 weight)
- **Bold Emphasis**: Inter Bold (700 weight)
- **Monospace**: Monaco, Menlo, Ubuntu Mono (code blocks)

### Font Sizes
- **H1**: 2.5rem
- **H2**: 2rem
- **H3**: 1.5rem
- **H4**: 1.25rem
- **Body**: 1rem (16px)
- **Code**: 0.9rem
- **Line Height**: 1.6

### Font Imports
```css
@import url('https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700&display=swap');
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap');
```

## Official Brand Colors (March 2023)

### Primary Colors
- **Orange**: #F47C6A (primary accent for highlighted text and call-to-action elements)
- **Blue**: #5F56DA (hyperlinked text and secondary accents)
- **Pink**: #FF1888 (alternative accent for emphasis)
- **Yellow**: #FFB648 (alternative accent for warnings and highlights)

### Secondary Colors
- **Liquorice**: #232236 (secondary background for dark mode)
- **Dark Blue Gradient**: #0E0B33 to #0D0B5D (dark backgrounds)

### Neutral Colors
- **White**: #FFFFFF (primary text on dark backgrounds)
- **Light Gray**: #F8F9FA (very light backgrounds)
- **Medium Gray**: #6C757D (secondary text)

## Light Mode Color Palette

```css
--uneeq-primary: #F47C6A;           /* Orange - primary accent */
--uneeq-blue: #5F56DA;              /* Blue - links and accents */
--uneeq-pink: #FF1888;              /* Pink - alternative accent */
--uneeq-yellow: #FFB648;            /* Yellow - warnings and highlights */
--uneeq-liquorice: #232236;         /* Secondary background */
--uneeq-dark-bg: #0E0B33;           /* Dark background */
--uneeq-light: #FFFFFF;             /* White text/backgrounds */
--uneeq-light-gray: #F8F9FA;        /* Very light gray */
--uneeq-gray: #6C757D;              /* Medium gray */
```

## Dark Mode Color Palette

Dark mode uses the official brand colors with carefully selected tone adjustments for readability and eye comfort.

```css
--dark-bg-primary: #0E0B33;         /* Official dark blue gradient start */
--dark-bg-secondary: #232236;       /* Liquorice - secondary background */
--dark-text-primary: #FFFFFF;       /* Pure white for high contrast */
--dark-text-secondary: #B0B7C3;     /* Light blue-gray for secondary text */
--dark-border: #3D3A4D;             /* Subtle borders */
--uneeq-accent-blue: #7F77E6;       /* Brightened blue for visibility */
--uneeq-accent-orange: #FF9B8F;     /* Brightened orange for visibility */
```

## Alert Colors

Standard semantic colors for alerts and status messaging:

- **Success**: #28A745 (green)
- **Warning**: #FFC107 (yellow)
- **Error**: #DC3545 (red)
- **Info**: #5F56DA (brand blue)

## Official Gradients

### Primary Gradient (Headers, CTAs)

Using official brand colors for maximum impact:

```css
/* Light Mode - Orange to Blue to Pink */
linear-gradient(135deg, #F47C6A 0%, #5F56DA 50%, #FF1888 100%)
```

### Dark Mode Gradient

Adjusted for visibility in dark backgrounds:

```css
/* Dark Mode - Brightened brand colors */
linear-gradient(135deg, #FF9B8F 0%, #7F77E6 50%, #FF6BA8 100%)
```

### Secondary Gradient

Alternative for step numbers and accents:

```css
/* Orange to Pink */
linear-gradient(135deg, #F47C6A, #FF1888)
```

## Component Styles

### Headers (H1, H2, H3, H4)
- **Heading 1**: Orange (#F47C6A) - for page titles
- **Heading 2-4**: Dark gray (#232236) - for section headers
- **H2 Underline**: Orange border-bottom (2px solid #F47C6A)
- **Font Weight**: 600-700 (Manrope)
- **Line Height**: 1.3 (tighter for impact)

### Navigation
- **Active Link Color**: #5F56DA (brand blue)
- **Border**: 3px solid #F47C6A (orange)
- **Hover State**: Slight opacity change or underline color shift
- **Sticky**: Yes (position: sticky, z-index: 90)

### Cards
- **Border Radius**: 12px
- **Padding**: 2rem
- **Shadow**: 0 8px 25px rgba(0, 0, 0, 0.1)
- **Border**: 1px solid rgba(244, 124, 106, 0.15) (orange with transparency)
- **Background**: White (light mode), #232236 (dark mode)

### Links
- **Light Mode Color**: #5F56DA (brand blue)
- **Dark Mode Color**: #7F77E6 (brightened blue)
- **Hover State**: Color transition + underline (orange #F47C6A)
- **Visited**: Slightly desaturated blue

### Alert Boxes
- **Border Radius**: 12px
- **Padding**: 1.5rem
- **Border Left**: 4px solid (color-specific by alert type)
- **Shadow**: 0 4px 15px rgba(0, 0, 0, 0.1)
- **Display**: Flex with icon and content
- **Info Background**: rgba(95, 86, 218, 0.1) (blue)
- **Success Background**: rgba(40, 167, 69, 0.1) (green)
- **Warning Background**: rgba(255, 182, 72, 0.15) (yellow)
- **Error Background**: rgba(220, 53, 69, 0.1) (red)

### Step Numbers
- **Shape**: Circle (3rem diameter)
- **Background**: Orange to Pink gradient (#F47C6A → #FF1888)
- **Shadow**: 0 4px 15px rgba(244, 124, 106, 0.3)
- **Font Weight**: 700 (bold)
- **Color**: White (#FFFFFF)
- **Border**: None

### Code Blocks (Light Mode)
- **Background**: #F8F9FA (light gray)
- **Text Color**: #232236 (liquorice)
- **Border Left**: 4px solid #F47C6A (orange)
- **Border Radius**: 8px
- **Font**: Monaco, Menlo, Ubuntu Mono (monospace)
- **Padding**: 1.5rem
- **Shadow**: 0 4px 15px rgba(0, 0, 0, 0.1)

### Code Blocks (Dark Mode)
- **Background**: #1A1530 (dark with slight blue tint)
- **Text Color**: #F8F9FA (off-white)
- **Border Left**: 4px solid #FF9B8F (brightened orange)
- **Shadow**: 0 4px 15px rgba(0, 0, 0, 0.4)

### Inline Code
- **Background**: #F8F9FA (light mode) or #2A2550 (dark mode)
- **Color**: #F47C6A (light mode) or #FF9B8F (dark mode)
- **Padding**: 0.25rem 0.5rem
- **Border Radius**: 4px
- **Font Weight**: 500

### Tables
- **Header Background**: Orange to Blue gradient (#F47C6A → #5F56DA)
- **Header Text**: White (#FFFFFF)
- **Row Hover**: rgba(244, 124, 106, 0.05) (orange tint)
- **Border**: 1px solid rgba(244, 124, 106, 0.15)
- **Shadow**: 0 4px 15px rgba(0, 0, 0, 0.1)

### Blockquotes
- **Background**: rgba(244, 124, 106, 0.1) (orange tint)
- **Border Left**: 4px solid #F47C6A (orange)
- **Border Radius**: 4px
- **Padding**: 1rem
- **Color**: Inherit from body text

## Logo Assets

### Local File Paths
- **Color Logo (Light Mode)**: `images/logos/logo-horizontal-color.png`
- **White Logo (Dark Mode)**: `images/logos/logo-white.png`
- **Favicon**: `images/logos/favicon.png` (40x40px)

### Logo Specifications
- **Width**: 330px maximum (primary locations)
- **Height**: 90px maximum (primary locations)
- **Secondary Locations**: 270px × 75px maximum
- **Format**: PNG with transparency
- **Object Fit**: Contain (preserves aspect ratio)

## SVG Graphics

### Architecture Diagrams
- **Style**: Enterprise-standard visual design
- **Primary Colors**: Use official brand colors (#F47C6A, #5F56DA, #FF1888)
- **Backgrounds**: Dark blue gradient for dark mode support
- **Border**: 2px solid with rounded corners
- **Responsive**: 100% width, auto height
- **Dark Mode**: CSS custom properties for color inversion

### Color Layers (SVG)
- **Users**: Blue (#5F56DA)
- **Frontend**: Orange (#F47C6A)
- **Backend**: Pink (#FF1888)
- **External Services**: Yellow (#FFB648)
- **Platform**: Blue gradient

## Responsive Breakpoints

### Desktop (768px and above)
- Full layout with sidebars
- 2-3 column grids
- Maximum content width: 1200px
- Full padding and spacing

### Tablet (481px - 767px)
- Single sidebar or mobile navigation
- Reduce header font sizes by 10-15%
- Single column for grids
- Reduced padding (1rem)

### Mobile (max-width: 480px)
- Stacked navigation (hamburger menu)
- Reduce all font sizes by 15-20%
- Minimize spacing (0.5rem)
- Single column everything
- Touch-friendly button sizes (min 44px)

## Dark Mode Implementation

### Toggle Button
- **Position**: Top-right corner (fixed)
- **Z-index**: 1000
- **Style**: Circular icon button with gradient background
- **Background**: Orange to Blue gradient (#F47C6A → #5F56DA)
- **Icon**: Sun (light mode) / Moon (dark mode)
- **Transition**: Smooth color transitions (0.3s ease)

### Color Scheme
- **Primary Background**: #0E0B33 (official dark blue)
- **Secondary Background**: #232236 (liquorice)
- **Primary Text**: #FFFFFF (pure white, 100% contrast)
- **Secondary Text**: #B0B7C3 (light blue-gray)
- **Borders**: #3D3A4D (subtle, low contrast)

### Accessibility in Dark Mode
- Text should maintain 4.5:1 contrast minimum (WCAG AA)
- Links should be 7:1 for visibility
- Avoid pure black (#000000) - use dark blue instead
- Reduce animation intensity for reduced-motion preference

## Accessibility & WCAG Compliance

### Contrast Ratios
- **Light Mode**: 7:1 minimum for body text (text-dark #232236 on white)
- **Dark Mode**: 4.5:1 minimum (white text on dark backgrounds)
- **Links**: 5:1 minimum contrast with surrounding text
- **Large Text**: 3:1 minimum acceptable (18pt+ or 14pt+ bold)

### Font Weights
- **Light Mode**: 400-600 (Manrope) for normal readability
- **Dark Mode**: 600-700 for better visibility (reduces halation effect)
- **Letter Spacing**: Normal (0em) light mode, 0.025em dark mode
- **Line Height**: 1.6 minimum for body text

### Color Accessibility
- Do NOT rely on color alone for information
- Use icons, patterns, or text labels in addition to color
- Test all gradients for sufficient contrast
- Ensure official brand colors meet contrast requirements

### Focus States
- **Outline**: 2px solid in contrasting color
- **Outline Offset**: 2px
- **Color**: #F47C6A (orange) for light mode, #FF9B8F for dark mode

## Animation & Transitions

### Standard Transitions
```css
transition: all 0.3s ease;
```

### Timing Functions
- Ease-in-out: 0.3s (default)
- Ease-out: 0.2s (quick responses)
- Ease-in: 0.4s (slow exits)

### Hover Effects
- **Buttons**: Transform translateY(-1px), opacity 0.9 → 1.0
- **Links**: Underline appears/color shift, border-bottom-color changes
- **Cards**: Subtle shadow increase (0 8px 25px → 0 12px 30px)
- **Icons**: Slight scale or rotation (1 → 1.05)

### Reduced Motion
```css
@media (prefers-reduced-motion: reduce) {
  * {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

## Grid System

### 2-Column Grid
```css
grid-template-columns: 1fr 1fr;
gap: 2rem;
```

### 3-Column Grid
```css
grid-template-columns: 1fr 1fr 1fr;
gap: 2rem;
```

### Responsive Behavior
- Desktop (768px+): Use 2-3 columns
- Tablet (481-767px): Use 1-2 columns
- Mobile (max 480px): Always 1 column
- Minimum gap: 1rem on mobile, 1.5-2rem on desktop

## Spacing System

### Base Unit: 1rem (16px)

### Margin/Padding Scale
- 0.25rem = 4px (small inline)
- 0.5rem = 8px (small)
- 1rem = 16px (base)
- 1.5rem = 24px (medium)
- 2rem = 32px (large)
- 3rem = 48px (extra large)
- 4rem = 64px (section)

### Application
- **Headings Bottom Margin**: 1rem
- **Paragraph Bottom Margin**: 1.5rem
- **Section Top Margin**: 2rem
- **Component Padding**: 1.5-2rem
- **Card Padding**: 2rem
- **List Item Margin**: 0.5rem bottom

## Best Practices

### Color Usage
1. **Use Official Brand Colors**: Orange (#F47C6A) for primary accents, Blue (#5F56DA) for links and secondary accents
2. **Gradients for Impact**: Use official gradients in headers, CTAs, and step numbers
3. **Remove Old Colors**: Never use #E91E63 (old magenta) or #e96057 (old red) - replace with official colors
4. **Dark Mode Support**: Brighten brand colors in dark mode (#FF9B8F for orange, #7F77E6 for blue)
5. **Consistency**: Maintain color meanings across all components

### Typography
1. **Manrope for Headings**: Use Manrope Bold (700) for all heading levels
2. **Inter for Body**: Use Inter Regular (400) for body text
3. **Hierarchy**: H1 (Orange), H2-H4 (Liquorice), Body (Dark Gray)
4. **Font Loading**: Include both Manrope and Inter in `<head>`

### Component Design
1. **Consistent Spacing**: Use 1rem base unit throughout
2. **Border Radius**: 12px for cards, 8px for code blocks, 4px for inline elements
3. **Shadows**: Use subtle shadows (0 4px 15px) for depth, increase on hover
4. **Mobile-First**: Design for mobile (480px), enhance for larger screens
5. **Touch Targets**: Minimum 44px for interactive elements on mobile

### Dark Mode
1. **Support Dark Mode**: Include `@media (prefers-color-scheme: dark)` or `.dark` class styles
2. **Use Liquorice Background**: #232236 for secondary surfaces in dark mode
3. **Brighten Accents**: Increase brightness of brand colors in dark mode
4. **Maintain Contrast**: Ensure 4.5:1 minimum contrast in dark mode
5. **Test Both Modes**: Always validate designs in light and dark modes

### Documentation
1. **SVG Over PNG**: Prefer SVG graphics for scalability and dark mode support
2. **Accessibility**: Include alt text for all images, ARIA labels for icons
3. **Code Examples**: Use syntax highlighting with official colors
4. **Links**: Make links obviously clickable (color + underline on hover)
5. **Images**: Use logo paths for local assets (`images/logos/...`)

### Performance
1. **Font Loading**: Use `display=swap` for Google Fonts to prevent FOIT
2. **Image Optimization**: Compress PNGs and SVGs before deployment
3. **CSS**: Minimize redundancy, use CSS custom properties for colors
4. **Gradients**: Use CSS gradients instead of image files where possible

## Troubleshooting

### Colors Look Wrong
- Verify official brand colors are being used (not old #E91E63 or #e96057)
- Check dark mode styles are applied in `.dark` class
- Ensure sufficient contrast (7:1 light mode, 4.5:1 dark mode)

### Logos Not Displaying
- Confirm logo paths are correct: `images/logos/logo-horizontal-color.png`
- Check that logo files exist in the project
- Verify logo classes (`.logo-light-mode` vs `.logo-dark-mode`) for proper mode switching

### Text Hard to Read
- Check font-family is Manrope (headings) or Inter (body)
- Verify font weight (400-600 light mode, 600-700 dark mode)
- Ensure line-height is at least 1.6
- Check letter-spacing is normal or 0.025em in dark mode

### Gradients Not Showing
- Use official gradient colors: #F47C6A, #5F56DA, #FF1888, #FFB648
- Verify gradient direction (135deg recommended)
- In dark mode, brighten colors (#FF9B8F, #7F77E6, #FF6BA8)
- Test in multiple browsers (some may have vendor prefixes needed)

## File Structure

```
docs/
├── DESIGN_SYSTEM.md              # This file - design system documentation
├── assets/
│   ├── miniprem.css             # Main CSS stylesheet (brand colors & components)
│   └── ue56_upgrade_instructions_backup.html
├── images/
│   └── logos/
│       ├── logo-horizontal-color.png  # Color logo (light mode)
│       ├── logo-white.png             # White logo (dark mode)
│       └── favicon.png                # 40x40px favicon
├── README.md                     # Documentation homepage
├── _coverpage.md                 # Cover page with logo
├── guides/
│   ├── getting-started.md
│   ├── kubernetes-overview.md
│   ├── kubernetes-eks.md
│   ├── kubernetes-aks.md
│   ├── kubernetes-multi-cloud.md
│   └── services.md
└── troubleshooting.md            # Troubleshooting guide
```

## Version History

- **v2.0** (March 2023): Brand refresh - Official UneeQ colors (Orange #F47C6A, Blue #5F56DA, Pink #FF1888, Yellow #FFB648), Manrope + Inter typography
- **v1.0** (Previous): Legacy colors and typography system (deprecated)

## Additional Resources

- [UneeQ Brand Guidelines](https://www.digitalhumans.com) - Official brand source
- [Google Fonts](https://fonts.google.com) - Manrope and Inter font families
- [WCAG Accessibility Standards](https://www.w3.org/WAI/WCAG21/quickref/) - Contrast and accessibility guidelines
