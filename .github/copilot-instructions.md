# GitHub Copilot Instructions for diermair.at

This repository contains the website for Forstbewirtschaftung Diermair, a forestry management business. These instructions help GitHub Copilot provide more relevant suggestions for this project.

## Project Overview

- **Site Type**: Business landing page for forestry management
- **Purpose**: Showcase services, contact information, and expertise in forest management
- **Framework**: Astro v5
- **Styling**: Vanilla CSS inside `<style>` tags in the `.astro` files.

## Technology Stack

- **Astro v5**: Used for building the site with its component-based architecture and zero-JS by default approach
- **Styling**: Vanilla CSS inside `<style>` tags in the `.astro` files.
- **View Transitions API**: For smooth page transitions where applicable
- **Static Site Generation**: Site is primarily statically generated

## Code Conventions

### General

- Use TypeScript for type safety where applicable
- Prefer functional components
- Follow semantic HTML practices
- Ensure accessibility compliance (WCAG standards)
- Maintain responsive design for all screen sizes

### Astro Components

- Use `.astro` files for page templates and components
- Follow Astro's component structure with frontmatter and template sections
- Use Astro islands sparingly and only when client-side interactivity is necessary
- Prefer static rendering when possible

```astro
---
// Frontmatter (JavaScript/TypeScript)
const { title } = Astro.props;
---

<!-- Template (HTML with directives) -->
<div class="component">
  <h2>{title}</h2>
  <slot />
</div>

<!-- Style (CSS) -->
<style>
.component {
  ...
}
</style>
```

### Project Structure

```
diermair.at/
├── public/           # Static assets
│   └── fonts/        # Font files
├── src/
│   ├── components/   # Reusable components
│   ├── images/       # Image files
│   ├── layouts/      # Page layouts
│   ├── pages/        # Page components (routes)
│   ├── styles/       # Global styles
├── astro.config.mjs  # Astro configuration
```

## Domain-Specific Knowledge

- Use forestry-related terminology appropriately
- Maintain an eco-friendly, nature-focused visual language
- Content should emphasize sustainable forestry practices
- Consider seasonal aspects of forestry work in content and imagery

## Performance Guidelines

- Optimize images using appropriate formats (WebP/AVIF) with fallbacks
- Lazy load off-screen images
- Minimize JavaScript usage
- Implement proper caching strategies
- Keep CSS lean 

## SEO Considerations

- Ensure all pages have proper meta tags
- Use semantic HTML structure
- Include structured data where appropriate
- Optimize for forestry-related keywords in Austria

## Browser Compatibility

- Ensure compatibility with modern browsers (last 2 versions)
- Provide graceful degradation for older browsers
- Test on mobile devices, especially iOS and Android

## Accessibility

- Maintain WCAG 2.1 AA compliance
- Use proper contrast ratios for text
- Ensure keyboard navigability
- Provide proper alt text for images
- Use semantic HTML elements

## Environment Variables

- Never expose sensitive information in client-side code

## Content Guidelines

- Use clear, concise language
- Highlight expertise in forest management
- Emphasize sustainable practices
- Feature high-quality images of forests and forestry work
- Include testimonials from satisfied clients when available
```

## GitHub Copilot Specific Instructions

When suggesting code:

1. Follow the established patterns in existing files
2. Prefer Astro's built-in features over additional dependencies
3. Suggest accessible markup following ARIA best practices
4. Consider image optimization techniques for forestry photographs
5. Use the established color palette from the styles/global.css
6. Suggest responsive designs that work well on mobile devices
7. Keep suggestions within the existing architectural patterns
8. Consider performance implications of your suggestions
9. Maintain the forestry-themed language and terminology