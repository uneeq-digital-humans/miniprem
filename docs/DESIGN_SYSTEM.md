# UneeQ Documentation Design System

This document defines the unified design language used across UneeQ documentation projects (Kiosk Application, MiniPrem, etc.).

## Typography

### Font Family
- **Primary**: `Manrope`, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif
- **Monospace**: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace
- **Import**: `https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700&display=swap`

### Font Sizes
- **Base**: 16px
- **H1**: 2.5rem
- **H2**: 2rem
- **H3**: 1.5rem
- **H4**: 1.25rem
- **Code**: 0.9rem
- **Line Height**: 1.6

## Color Palette

### UneeQ Brand Colors (Light Mode)
```css
--uneeq-primary: #E91E63;           /* Deep magenta - primary accent */
--uneeq-primary-light: #FF7F7F;     /* Light coral - secondary accent */
--uneeq-secondary: #e96057;         /* Brand red/orange */
--uneeq-secondary-light: #FFA726;   /* Light orange */
--uneeq-dark-navy: #0B0941;         /* Primary dark */
--uneeq-accent-purple: #5F56D9;     /* Accent purple */
--uneeq-dark-bg: #0e0b33;           /* Dark background */
--uneeq-dark: #2C3E50;              /* Secondary dark navy */
--uneeq-dark-light: #34495E;        /* Lighter navy */
--uneeq-light: #FFFFFF;             /* Clean white */
--uneeq-light-gray: #F8F9FA;        /* Very light gray */
--uneeq-gray: #6C757D;              /* Medium gray */
```

### Dark Mode Colors
```css
--dark-bg-primary: #0e0b33;
--dark-bg-secondary: #1a1747;
--dark-text-primary: #F8F9FA;       /* Off-white */
--dark-text-secondary: #B0B7C3;
--dark-border: #2a2550;
--uneeq-accent-purple-dark: #6B64D6;  /* Desaturated for eye comfort */
--uneeq-dark-navy-dark: #1A1555;      /* Lighter dark navy */
```

### Alert Colors
- **Success**: #28A745
- **Warning**: #FFC107
- **Error**: #DC3545
- **Info**: var(--uneeq-primary)

## Gradients

### Header Gradient (Light Mode)
```css
linear-gradient(135deg, #5F56D9 0%, #8B5FF8 25%, #B84BF5 50%, #E537E8 75%, #F41788 100%)
```

### Header Gradient (Dark Mode)
```css
linear-gradient(135deg, #4338CA 0%, #6366F1 25%, #7C3AED 50%, #8B5CF6 75%, #A855F7 100%)
```

### Step Number Gradient
```css
linear-gradient(135deg, var(--uneeq-primary), var(--uneeq-secondary))
```

## Component Styles

### Headers
- **Background**: Purple-to-pink gradient (light mode), desaturated purple (dark mode)
- **Text Color**: White (high contrast)
- **Sticky**: Yes (position: sticky, z-index: 100)
- **Logo**: 40x40px UneeQ favicon

### Navigation
- **Border**: 3px solid primary color
- **Active State**: Gradient background with pink accent
- **Sticky**: Yes (below header, z-index: 90)

### Cards
- **Border Radius**: 12px
- **Padding**: 2rem
- **Shadow**: 0 8px 25px rgba(0,0,0,0.1)
- **Border**: 1px solid rgba(233, 30, 99, 0.1)

### Alert Boxes
- **Border Radius**: 12px
- **Padding**: 1.5rem
- **Border Left**: 4px solid (color-specific)
- **Shadow**: 0 4px 15px rgba(0,0,0,0.1)
- **Display**: Flex with icon and content

### Step Numbers
- **Shape**: Circle (3rem diameter)
- **Background**: Pink-to-orange gradient
- **Shadow**: 0 4px 15px rgba(233, 30, 99, 0.3)
- **Font Weight**: 700
- **Color**: White

### Code Blocks
- **Background**: Light gray (light mode), dark navy (dark mode)
- **Border Left**: 4px solid pink (light mode) or purple (dark mode)
- **Border Radius**: 8px
- **Font**: Monaco, Menlo, Ubuntu Mono
- **Padding**: 1.5rem
- **Copy Button**: Positioned absolute, top-right

## Logo Assets

### Files
- **Favicon**: `images/uneeq-favicon.png` (40x40px)
- **Full Logo**: `images/UneeQ-logo.png`
- **Architecture Diagram**: SVG with CSS custom properties for dark mode support

### URLs (from Kiosk Application)
- Favicon: `https://kiosk-application-3b36ac.gitlab.io/images/uneeq-favicon.png`
- Logo: `https://kiosk-application-3b36ac.gitlab.io/images/UneeQ-logo.png`

## SVG Graphics

### Architecture Diagrams
- **Style**: Enterprise-standard visual design
- **Color Layers**:
  - Users: Blue shades
  - Frontend: Green shades
  - Backend: Red shades
  - External Services: Cyan shades
  - Platform: Rose shades
- **Dark Mode**: CSS custom properties for color inversion
- **Responsive**: 100% width, auto height
- **Border**: Light border with rounded corners

## Responsive Breakpoints

### Mobile (max-width: 768px)
- Stack navigation vertically
- Reduce header font size
- Center align headers
- Single column grids
- Reduce padding

### Mobile Small (max-width: 480px)
- Further reduce font sizes
- Minimize spacing
- Stack all components

## Dark Mode Toggle

### Position
- **Fixed**: top-right corner
- **Z-index**: 1000
- **Style**: Glass morphism (backdrop blur)
- **Icons**: Sun (light mode), Moon (dark mode)
- **Transition**: Smooth color transitions

## Accessibility

### Contrast Ratios
- Light mode: 7:1 minimum
- Dark mode: 4.5:1 minimum (off-white text to reduce halation)

### Font Weights
- Dark mode: Slightly heavier (700 vs 600) for better readability
- Letter spacing: Increased in dark mode (0.025em)

## Animation & Transitions

### Standard Transitions
```css
transition: all 0.3s ease;
```

### Hover Effects
- Transform: translateY(-1px) for buttons
- Opacity: Subtle changes (0.8 → 1.0)
- Border: Solid → Colored

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

### Responsive
- Mobile: Always 1 column

## Best Practices

1. **Use UneeQ Brand Colors**: Pink (#E91E63) for primary, orange (#e96057) for secondary
2. **Gradients for Impact**: Headers, buttons, and step numbers use gradients
3. **Consistent Spacing**: 1rem base unit, 1.5-2rem for sections
4. **Mobile-First**: Design for mobile, enhance for desktop
5. **Dark Mode by Default**: Support dark mode in all components
6. **SVG over PNG**: Prefer SVG graphics for scalability and dark mode support
7. **Accessibility**: Maintain WCAG AA contrast ratios minimum
