-- Keyframes are now uploaded as a burst per flagged moment (the frames the AI
-- reviews), not one frame per moment. Add an index so the review/history view
-- can group a round's frames back into moments — correction_ref already holds
-- the correction's text.
alter table public.keyframes
  add column if not exists correction_index int;

create index if not exists keyframes_round_moment_idx
  on public.keyframes (round_id, correction_index, timestamp_ms);
