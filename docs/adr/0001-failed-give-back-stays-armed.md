# A failed give-back keeps the setting armed

The guard gives back a raise when the CPU stays hot, but a reversal can fail:
`nvidia-smi` needs root that a user service does not have, and a profile write
can be refused by the firmware. An entry whose give-back fails stays in the
armed set, so the next poll retries it, and the latch never reports giving back
something that did not land.

## Considered options

Disarming on failure — the original behaviour — was rejected because it cleared
the entry and latched regardless, leaving the latch summary claiming a
give-back that never happened. That is the same class of error the abandon path
exists to prevent on the raise side.

Folding failure into deferral was rejected because the two need different log
outcomes, even though both keep the entry armed.

## Consequences

An entry can stay armed indefinitely if its reversal never succeeds. The retry
is not the next poll: `monitor_poll` clears the sustain timer whenever the
guard fires, so the next attempt waits for another full `GUARD_SUSTAIN` of
continuous heat, and a machine that cools in between waits for the hot episode
after that. The armed set is therefore a record, not a fast retry queue. That
is accepted, because a reversal that keeps failing is worth leaving visible in
the armed set rather than silently discarding.
