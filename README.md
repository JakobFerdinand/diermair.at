# diermair.at

[The homepage](https://diermair.at) of Paul Diermair Waldbewirtschaftung.

## Infrastructure

The Azure estate is managed with Bicep under `infrastructure/` (`main.bicep` is
resource-group scoped, `main-subscription.bicep` covers the cost budget). Changes
to `infrastructure/**` deploy automatically via the `infra-deploy.yml` workflow,
which previews with `what-if` on PRs and applies on `main`. See
`docs/plans/infrastructure-as-code.md` for the adoption plan.
