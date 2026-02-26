import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

const leistungen = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/data/leistungen' }),
  schema: z.object({
    title: z.string(),
    icon: z.enum(['MessageSquare', 'Axe', 'Crosshair', 'Trees']),
    teaser: z.string(),
    order: z.number(),
  }),
});

export const collections = { leistungen };
