import os

base = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(base)
schema_path = os.path.join(root, 'supabase', 'schema.sql')
out_path = os.path.join(root, 'supabase', 'add_multi_scale_scoring.sql')

with open(schema_path, encoding='utf-8') as f:
    lines = f.read().splitlines()

header = '''-- Migration: multi-scale scoring + image items + neutral public metadata
-- Adds scale metadata and item images, then refreshes the public read and
-- server-side scoring functions. Safe to re-run.

alter table public.assessments
  add column if not exists scale_meta jsonb not null default '[]'::jsonb;

alter table public.assessment_items
  add column if not exists image_url text not null default '',
  add column if not exists scales jsonb not null default '[]'::jsonb;

'''

# Extract from the public reader through the end of submit_assessment.
start = next(i for i, line in enumerate(lines) if line.startswith('create or replace function public.get_assessment_public'))
end = next(i for i, line in enumerate(lines) if line.startswith('-- Admin-only account creation'))
body = '\n'.join(lines[start:end]).rstrip() + '\n'

with open(out_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(header + body)

print(out_path)
