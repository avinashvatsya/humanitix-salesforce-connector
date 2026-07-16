# Summary

<!-- What does this change do and why? -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Mapping/config change (CMT)
- [ ] Docs
- [ ] Refactor / chore

## Checklist

- [ ] `npm run prettier:verify` passes
- [ ] `npm run test:unit` (LWC Jest) passes
- [ ] Apex tests pass in a scratch org (`sf apex run test -l RunLocalTests -c`)
- [ ] If I changed a custom object/field, I updated `scripts/dev/generate-metadata.py` and re-ran it (so permission-set FLS stays in sync)
- [ ] If I changed default mappings, I updated `scripts/dev/generate-default-mappings.py` and re-ran it
- [ ] Docs updated where relevant

## Notes for reviewers

<!-- Anything to call out -->
