Round N Wave2 JAM-7 private visual fixture.
Run from the shared project:
  python3 render.py --seat jam-7 --script res://scenes/ui_preview_n/capture.gd --name round-n-wave2-ui --timeout 60

15 PNGs go to JAM-7 state/exports/round-n-wave2. Uses the real museum, protagonist,
repair panel, equipment and TimeCore. Player/weapon adapters supply display state
without using the still-unmigrated N1 arena. No simulation/full-run claim.

Owned GUI checks: python3 check.py --seat jam-7 --suite ui_n
Full integration instructions: scenes/ui/INTEGRATION.txt (Round N section first).
